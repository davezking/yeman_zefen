import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_units.dart';

/// How a rewarded ad ended.
enum RewardedResult {
  /// The player watched it and earned the hint.
  earned,

  /// The player closed it before the reward.
  notFinished,

  /// No ad could be shown.
  unavailable,
}

/// Full-screen ads: one interstitial and one rewarded ad kept loaded, each loaded again after it
/// shows. Nothing is requested before [start], which the consent flow calls once Google's consent
/// check allows ad requests.
abstract class AdService {
  /// Starts loading ads. Safe to call more than once.
  Future<void> start();

  /// An interstitial is loaded and can show now.
  bool get interstitialReady;

  /// A rewarded ad is loaded. The hint button shows only while this is true.
  ValueListenable<bool> get rewardedReady;

  /// Shows the loaded interstitial. Completes when the player closes it: true when it was shown.
  Future<bool> showInterstitial();

  /// Shows the loaded rewarded ad. Completes when the player closes it.
  Future<RewardedResult> showRewarded();

  void dispose();
}

/// A build without ad units: never any ads.
class NoAdService implements AdService {
  NoAdService();

  final _rewardedReady = ValueNotifier(false);

  @override
  Future<void> start() async {}

  @override
  bool get interstitialReady => false;

  @override
  ValueListenable<bool> get rewardedReady => _rewardedReady;

  @override
  Future<bool> showInterstitial() async => false;

  @override
  Future<RewardedResult> showRewarded() async => RewardedResult.unavailable;

  @override
  void dispose() => _rewardedReady.dispose();
}

/// [AdService] on the Google Mobile Ads SDK. Consent is the UMP SDK's job: its answer travels with
/// every request, so personalized ads only reach players who agreed.
class GoogleAdService implements AdService {
  GoogleAdService(this.units);

  final AdUnits units;

  /// A failed load is tried again after this, doubling up to [_maxRetry].
  static const _firstRetry = Duration(seconds: 30);
  static const _maxRetry = Duration(minutes: 10);

  /// Google's guidance: a loaded ad older than this may no longer be served.
  static const _maxAge = Duration(hours: 1);

  /// The reward can be reported just after the ad closes. A close without one waits this long for it
  /// before counting the ad as not finished.
  static const _lateRewardWait = Duration(milliseconds: 800);

  Future<void>? _started;
  var _disposed = false;

  final _interstitial = _Slot<InterstitialAd>();
  final _rewarded = _Slot<RewardedAd>();
  final _rewardedReady = ValueNotifier(false);

  @override
  Future<void> start() => _started ??= _start();

  Future<void> _start() async {
    try {
      if (units.testDeviceIds.isNotEmpty) {
        await MobileAds.instance.updateRequestConfiguration(RequestConfiguration(testDeviceIds: units.testDeviceIds));
      }
      await MobileAds.instance.initialize();
    } catch (e) {
      debugPrint('ads: the SDK did not start: $e');
      _started = null;
      return;
    }
    _loadInterstitial();
    _loadRewarded();
  }

  @override
  bool get interstitialReady => _interstitial.ad != null;

  @override
  ValueListenable<bool> get rewardedReady => _rewardedReady;

  void _loadInterstitial() {
    if (_disposed || !_interstitial.canLoad) return;
    _interstitial.loading = true;
    unawaited(
      InterstitialAd.load(
        adUnitId: units.interstitial,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) => _interstitial.loaded(ad, disposed: _disposed, onExpired: _loadInterstitial),
          onAdFailedToLoad: (error) => _interstitial.failed(error, _loadInterstitial),
        ),
      ).catchError((Object e) => _interstitial.failed(e, _loadInterstitial)),
    );
  }

  void _loadRewarded() {
    if (_disposed || !_rewarded.canLoad) return;
    _rewarded.loading = true;
    unawaited(
      RewardedAd.load(
        adUnitId: units.rewarded,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _rewarded.loaded(
              ad,
              disposed: _disposed,
              onExpired: () {
                _syncRewarded();
                _loadRewarded();
              },
            );
            _syncRewarded();
          },
          onAdFailedToLoad: (error) => _rewarded.failed(error, _loadRewarded),
        ),
      ).catchError((Object e) => _rewarded.failed(e, _loadRewarded)),
    );
  }

  void _syncRewarded() {
    if (!_disposed) _rewardedReady.value = _rewarded.ad != null;
  }

  @override
  Future<bool> showInterstitial() async {
    final ad = _interstitial.take();
    if (ad == null) return false;
    final done = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        unawaited(ad.dispose());
        if (!done.isCompleted) done.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        unawaited(ad.dispose());
        if (!done.isCompleted) done.complete(false);
      },
    );
    try {
      await ad.show();
    } catch (_) {
      unawaited(ad.dispose());
      if (!done.isCompleted) done.complete(false);
    }
    final shown = await done.future;
    _loadInterstitial();
    return shown;
  }

  @override
  Future<RewardedResult> showRewarded() async {
    final ad = _rewarded.take();
    _syncRewarded();
    if (ad == null) return RewardedResult.unavailable;
    var earned = false;
    var dismissed = false;
    Timer? lateReward;
    final done = Completer<RewardedResult>();
    void finish(RewardedResult result) {
      lateReward?.cancel();
      if (done.isCompleted) return;
      done.complete(result);
      unawaited(ad.dispose());
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) {
        dismissed = true;
        if (earned) return finish(RewardedResult.earned);
        // Kept until the wait is over, so a late reward is still delivered.
        lateReward = Timer(_lateRewardWait, () => finish(RewardedResult.notFinished));
      },
      onAdFailedToShowFullScreenContent: (_, _) => finish(RewardedResult.unavailable),
    );
    try {
      await ad.show(
        onUserEarnedReward: (_, _) {
          earned = true;
          if (dismissed) finish(RewardedResult.earned);
        },
      );
    } catch (_) {
      finish(RewardedResult.unavailable);
    }
    final result = await done.future;
    _loadRewarded();
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    _interstitial.dispose();
    _rewarded.dispose();
    _rewardedReady.dispose();
  }
}

/// One loaded (or loading) ad, its retry schedule, and its expiry.
class _Slot<T extends AdWithoutView> {
  T? ad;
  var loading = false;
  var retry = GoogleAdService._firstRetry;
  Timer? retryTimer;
  Timer? expiryTimer;

  bool get canLoad => ad == null && !loading && retryTimer == null;

  /// Keeps [next] until it is shown or too old to be served; then it is dropped and [onExpired]
  /// loads a fresh one.
  void loaded(T next, {required bool disposed, required void Function() onExpired}) {
    loading = false;
    retry = GoogleAdService._firstRetry;
    if (disposed) {
      unawaited(next.dispose());
      return;
    }
    ad = next;
    expiryTimer?.cancel();
    expiryTimer = Timer(GoogleAdService._maxAge, () {
      expiryTimer = null;
      final stale = ad;
      ad = null;
      if (stale != null) unawaited(stale.dispose());
      onExpired();
    });
  }

  void failed(Object error, void Function() load) {
    loading = false;
    debugPrint('ads: load failed, retrying in ${retry.inSeconds} s: $error');
    retryTimer = Timer(retry, () {
      retryTimer = null;
      load();
    });
    retry = Duration(milliseconds: min(retry.inMilliseconds * 2, GoogleAdService._maxRetry.inMilliseconds));
  }

  /// Hands over the loaded ad, to show once.
  T? take() {
    final taken = ad;
    ad = null;
    expiryTimer?.cancel();
    expiryTimer = null;
    return taken;
  }

  void dispose() {
    retryTimer?.cancel();
    retryTimer = null;
    expiryTimer?.cancel();
    expiryTimer = null;
    final held = ad;
    ad = null;
    if (held != null) unawaited(held.dispose());
  }
}
