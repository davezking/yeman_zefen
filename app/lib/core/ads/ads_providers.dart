import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/remote_config.dart';
import 'ad_policy.dart';
import 'ad_service.dart';
import 'ad_units.dart';
import 'consent_service.dart';

final adUnitsProvider = Provider<AdUnits>((ref) => AdUnits.fromConfig());

/// The ads. A build without ad units (tests, a prod build before AdMob is set up) has none.
final adServiceProvider = Provider<AdService>((ref) {
  final units = ref.watch(adUnitsProvider);
  final AdService service = units.configured ? GoogleAdService(units) : NoAdService();
  ref.onDispose(service.dispose);
  return service;
});

/// When interstitials show. Kept for the whole run, so the round count carries over sessions.
final adPolicyProvider = Provider<AdPolicy>(
  (ref) => AdPolicy(everyRounds: () => ref.read(remoteConfigProvider).interstitialEveryRounds),
);

final consentServiceProvider = Provider<ConsentService>((ref) {
  final units = ref.watch(adUnitsProvider);
  final service = ConsentService(
    GoogleConsentPlatform(ios: defaultTargetPlatform == TargetPlatform.iOS, testDeviceIds: units.testDeviceIds),
    enabled: units.configured,
    onAdsAllowed: () => ref.read(adServiceProvider).start(),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// A rewarded ad is loaded: the round offers the hint.
final rewardedReadyProvider = Provider<bool>((ref) => _listen(ref, ref.watch(adServiceProvider).rewardedReady));

/// Settings shows "Ad privacy choices".
final privacyOptionsRequiredProvider = Provider<bool>(
  (ref) => _listen(ref, ref.watch(consentServiceProvider).privacyOptionsRequired),
);

T _listen<T>(Ref ref, ValueListenable<T> source) {
  void changed() => ref.invalidateSelf();
  source.addListener(changed);
  ref.onDispose(() => source.removeListener(changed));
  return source.value;
}

/// Read once at start-up: refreshes the consent status, which starts the ads where they are allowed.
final adsStarterProvider = Provider<void>((ref) {
  unawaited(ref.read(consentServiceProvider).startup());
});
