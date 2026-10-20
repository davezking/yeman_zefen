/// Build-time configuration, injected with `--dart-define-from-file=config/<flavor>.json`.
class AppConfig {
  const AppConfig._();

  static const flavor = String.fromEnvironment('APP_FLAVOR');
  static const apiBase = String.fromEnvironment('API_BASE');
  /// Where the update screen sends players (the Play Store listing). Empty: the screen shows no button.
  static const storeUrl = String.fromEnvironment('STORE_URL');
  /// The OAuth web client id of the Firebase project, which Google Sign-In on Android needs to
  /// return an ID token. Empty: Google sign-in is not offered.
  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
  /// The privacy policy page, linked from Settings. Empty until the policy is published.
  static const privacyUrl = String.fromEnvironment('PRIVACY_URL');
  /// Offer Sign in with Apple on Android too (it is always offered on iOS).
  static const appleOnAndroid = bool.fromEnvironment('APPLE_ON_ANDROID');

  /// AdMob ad unit ids per platform. Google's test units in the dev flavor. Empty: the app shows no
  /// ads and asks for no ad consent. The AdMob app ids are native config (`docs/ops.md`).
  static const admobInterstitialAndroid = String.fromEnvironment('ADMOB_INTERSTITIAL_ANDROID');
  static const admobRewardedAndroid = String.fromEnvironment('ADMOB_REWARDED_ANDROID');
  static const admobInterstitialIos = String.fromEnvironment('ADMOB_INTERSTITIAL_IOS');
  static const admobRewardedIos = String.fromEnvironment('ADMOB_REWARDED_IOS');
  /// Dev only: makes Google's consent check treat test devices as in the EEA (`eea`) or outside it
  /// (`other`). Empty: the real location decides.
  static const umpDebugGeography = String.fromEnvironment('UMP_DEBUG_GEOGRAPHY');
  /// Dev only: comma-separated hashed device ids that get test ads and the debug geography. The
  /// ads SDK logs a phone's id the first time it asks for an ad.
  static const adTestDeviceIds = String.fromEnvironment('AD_TEST_DEVICE_IDS');

  /// Fails fast when the app was built without a config file, rather than
  /// sending requests to an empty base URL.
  static void assertConfigured() {
    if (flavor.isEmpty || apiBase.isEmpty) {
      throw StateError(
        'Missing build config. Run with --dart-define-from-file=config/<dev|prod>.json',
      );
    }
  }
}
