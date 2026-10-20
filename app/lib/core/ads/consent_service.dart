import 'dart:async';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/app_config.dart';

/// What Google's consent check (UMP) says about this player.
enum UmpStatus { unknown, required, notRequired, obtained }

/// Google's User Messaging Platform and Apple's App Tracking Transparency, behind a seam so the
/// consent flow can be tested without either.
abstract class ConsentPlatform {
  /// Asks Google whether consent is needed here. Throws when it cannot tell (offline).
  Future<void> requestInfoUpdate();

  Future<UmpStatus> status();

  /// Ads may be requested: consent was given, is not needed here, or a past answer still holds.
  Future<bool> canRequestAds();

  /// The player must be able to change their choice from Settings.
  Future<bool> privacyOptionsRequired();

  /// Google's consent form, when it is required. Completes when the player closes it.
  Future<void> showFormIfRequired();

  /// Google's privacy options form, for Settings › Ad privacy choices.
  Future<void> showPrivacyOptionsForm();

  /// iOS 14+: the tracking question has not been asked yet. Always false elsewhere.
  Future<bool> trackingUndetermined();

  /// Shows Apple's tracking question.
  Future<void> requestTracking();
}

/// Where the player is in the consent flow after a finished game.
enum ConsentAsk {
  /// Nothing to ask: go to Results.
  none,

  /// Google says consent is required: the consent screen (H15), Google's form, then on iOS the
  /// tracking question.
  form,

  /// Only Apple's tracking question is due (iOS, outside the regions that need the form).
  tracking,
}

/// Runs the ad consent flow.
///
/// On every start the consent status is refreshed, without showing anything: no prompt stands
/// between opening the app and the first round. Ads start loading only once Google says ads may be
/// requested, so no ad request is ever made before the consent check. Where consent is required,
/// the form comes after a finished game, before Results (`docs/design/screens.md`, H15), and again
/// after each game until it is answered. On iOS, Apple's tracking question follows Google's form,
/// as Google recommends.
class ConsentService {
  ConsentService(this.platform, {required this.onAdsAllowed, this.enabled = true});

  final ConsentPlatform platform;

  /// Starts the ads. Called whenever the consent check allows ad requests.
  final Future<void> Function() onAdsAllowed;

  /// False for a build without ads: nothing is asked.
  final bool enabled;

  /// Settings shows "Ad privacy choices" only while this is true.
  final privacyOptionsRequired = ValueNotifier(false);

  Future<void>? _startup;
  var _status = UmpStatus.unknown;
  var _trackingDue = false;

  /// Refreshes the consent status. Call once when the app starts; later calls return the same run.
  Future<void> startup() => _startup ??= _runStartup();

  Future<void> _runStartup() async {
    if (!enabled) return;
    try {
      await platform.requestInfoUpdate();
    } catch (e) {
      // Offline, or Google did not answer: the answer stored from an earlier run still applies.
      debugPrint('consent: no update: $e');
    }
    await _refresh();
  }

  /// Whether a finished game asks anything before Results. Synchronous, from the last check, so
  /// Results is not held up waiting for a platform call.
  ConsentAsk get askAfterGame {
    if (!enabled) return ConsentAsk.none;
    if (_status == UmpStatus.required) return ConsentAsk.form;
    if (_trackingDue) return ConsentAsk.tracking;
    return ConsentAsk.none;
  }

  /// "Continue" on the consent screen: Google's form, then Apple's tracking question.
  Future<void> showForm() async {
    try {
      await platform.showFormIfRequired();
    } catch (e) {
      debugPrint('consent: the form failed: $e');
    }
    await requestTracking();
    await _refresh();
  }

  /// Apple's tracking question, when it has not been asked yet.
  Future<void> requestTracking() async {
    try {
      if (await platform.trackingUndetermined()) await platform.requestTracking();
    } catch (e) {
      debugPrint('consent: tracking question failed: $e');
    }
    _trackingDue = false;
  }

  /// Settings › Ad privacy choices.
  Future<void> openPrivacyOptions() async {
    try {
      await platform.showPrivacyOptionsForm();
    } catch (e) {
      debugPrint('consent: privacy options failed: $e');
    }
    await _refresh();
  }

  Future<void> _refresh() async {
    try {
      _status = await platform.status();
      _trackingDue = await platform.trackingUndetermined();
      privacyOptionsRequired.value = await platform.privacyOptionsRequired();
      if (await platform.canRequestAds()) await onAdsAllowed();
    } catch (e) {
      debugPrint('consent: status unreadable: $e');
    }
  }

  void dispose() => privacyOptionsRequired.dispose();
}

/// [ConsentPlatform] on Google's UMP SDK (from `google_mobile_ads`) and `app_tracking_transparency`.
class GoogleConsentPlatform implements ConsentPlatform {
  GoogleConsentPlatform({required this.ios, this.testDeviceIds = const []});

  final bool ios;
  final List<String> testDeviceIds;

  ConsentRequestParameters _parameters() {
    final geography = switch (AppConfig.umpDebugGeography) {
      'eea' => DebugGeography.debugGeographyEea,
      'other' => DebugGeography.debugGeographyOther,
      _ => null,
    };
    // Debug settings only ever apply to the listed test devices, and only in the dev flavor.
    if (geography == null || AppConfig.flavor != 'dev') return ConsentRequestParameters();
    return ConsentRequestParameters(
      consentDebugSettings: ConsentDebugSettings(debugGeography: geography, testIdentifiers: testDeviceIds),
    );
  }

  @override
  Future<void> requestInfoUpdate() {
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      _parameters(),
      () => done.complete(),
      (error) => done.completeError(StateError('${error.errorCode}: ${error.message}')),
    );
    return done.future;
  }

  @override
  Future<UmpStatus> status() async => switch (await ConsentInformation.instance.getConsentStatus()) {
    ConsentStatus.required => UmpStatus.required,
    ConsentStatus.notRequired => UmpStatus.notRequired,
    ConsentStatus.obtained => UmpStatus.obtained,
    ConsentStatus.unknown => UmpStatus.unknown,
  };

  @override
  Future<bool> canRequestAds() => ConsentInformation.instance.canRequestAds();

  @override
  Future<bool> privacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() == PrivacyOptionsRequirementStatus.required;

  @override
  Future<void> showFormIfRequired() {
    final done = Completer<void>();
    unawaited(ConsentForm.loadAndShowConsentFormIfRequired((error) {
      if (error != null) debugPrint('consent: form error ${error.errorCode}: ${error.message}');
      if (!done.isCompleted) done.complete();
    }).catchError((Object e) {
      if (!done.isCompleted) done.completeError(e);
    }));
    return done.future;
  }

  @override
  Future<void> showPrivacyOptionsForm() {
    final done = Completer<void>();
    unawaited(ConsentForm.showPrivacyOptionsForm((error) {
      if (error != null) debugPrint('consent: privacy form error ${error.errorCode}: ${error.message}');
      if (!done.isCompleted) done.complete();
    }).catchError((Object e) {
      if (!done.isCompleted) done.completeError(e);
    }));
    return done.future;
  }

  @override
  Future<bool> trackingUndetermined() async =>
      ios && await AppTrackingTransparency.trackingAuthorizationStatus == TrackingStatus.notDetermined;

  @override
  Future<void> requestTracking() async {
    if (ios) await AppTrackingTransparency.requestTrackingAuthorization();
  }
}
