import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

/// The ad units this build shows, for the platform it runs on.
@immutable
class AdUnits {
  const AdUnits({required this.interstitial, required this.rewarded, this.testDeviceIds = const []});

  /// From the build config (`config/<flavor>.json`).
  factory AdUnits.fromConfig({TargetPlatform? platform}) {
    final ios = (platform ?? defaultTargetPlatform) == TargetPlatform.iOS;
    return AdUnits(
      interstitial: ios ? AppConfig.admobInterstitialIos : AppConfig.admobInterstitialAndroid,
      rewarded: ios ? AppConfig.admobRewardedIos : AppConfig.admobRewardedAndroid,
      testDeviceIds: splitIds(AppConfig.adTestDeviceIds),
    );
  }

  final String interstitial;
  final String rewarded;
  final List<String> testDeviceIds;

  /// Both units are set. Without them the app has no ads and asks for no consent.
  bool get configured => interstitial.isNotEmpty && rewarded.isNotEmpty;

  static List<String> splitIds(String ids) => [
    for (final id in ids.split(',')) if (id.trim().isNotEmpty) id.trim(),
  ];
}
