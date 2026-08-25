/// Environment configuration for the Shopkeeper App.
///
/// The API base URL is injected at build time via `--dart-define`, mirroring
/// the Customer App convention. Never embed production secrets here.
class EnvConfig {
  EnvConfig._();

  static const String _baseUrl = String.fromEnvironment(
    'SHOPKEEPER_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const bool useMockData = bool.fromEnvironment(
    'SHOPKEEPER_USE_MOCK',
    defaultValue: false,
  );

  /// Backend base URL, e.g. `http://10.0.2.2:8000` (Android emulator → host).
  static String get apiBaseUrl => _baseUrl;
}
