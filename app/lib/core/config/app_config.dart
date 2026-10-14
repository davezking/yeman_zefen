/// Build-time configuration, injected with `--dart-define-from-file=config/<flavor>.json`.
class AppConfig {
  const AppConfig._();

  static const flavor = String.fromEnvironment('APP_FLAVOR');
  static const apiBase = String.fromEnvironment('API_BASE');

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
