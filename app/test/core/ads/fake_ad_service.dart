import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:yeman_zefen/core/ads/ad_service.dart';

/// An [AdService] with no SDK. Tests load ads, and close the one on screen, by hand.
class FakeAdService implements AdService {
  final rewarded = ValueNotifier(false);

  /// An interstitial is loaded.
  var interstitialLoaded = false;

  /// A closed interstitial is replaced at once, as the real service reloads one.
  var reloadInterstitial = true;

  /// The hint is given without an ad, as in a build without ad units.
  var hints = false;

  var started = 0;
  var interstitialShows = 0;
  var rewardedShows = 0;

  Completer<bool>? _interstitial;
  Completer<RewardedResult>? _rewarded;

  bool get interstitialShowing => _interstitial != null;
  bool get rewardedShowing => _rewarded != null;

  @override
  Future<void> start() async => started++;

  @override
  bool get interstitialReady => interstitialLoaded;

  @override
  ValueListenable<bool> get rewardedReady => rewarded;

  @override
  bool get freeHints => hints;

  @override
  Future<bool> showInterstitial() {
    if (!interstitialLoaded) return Future.value(false);
    interstitialLoaded = false;
    interstitialShows++;
    final c = Completer<bool>();
    _interstitial = c;
    return c.future;
  }

  /// The player closes the interstitial.
  void closeInterstitial() {
    final c = _interstitial!;
    _interstitial = null;
    if (reloadInterstitial) interstitialLoaded = true;
    c.complete(true);
  }

  @override
  Future<RewardedResult> showRewarded() {
    if (!rewarded.value) return Future.value(RewardedResult.unavailable);
    rewarded.value = false;
    rewardedShows++;
    final c = Completer<RewardedResult>();
    _rewarded = c;
    return c.future;
  }

  /// The rewarded ad ends with [result].
  void closeRewarded(RewardedResult result) {
    final c = _rewarded!;
    _rewarded = null;
    c.complete(result);
  }

  @override
  void dispose() => rewarded.dispose();
}
