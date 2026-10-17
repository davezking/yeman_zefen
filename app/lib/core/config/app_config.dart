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
  /// Offer Sign in with Apple on Android too (it is always offered on iOS).
  static const appleOnAndroid = bool.fromEnvironment('APPLE_ON_ANDROID');

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
