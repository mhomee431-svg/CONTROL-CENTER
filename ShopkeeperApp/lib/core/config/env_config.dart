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

  // ────────────────────────────────────────────────────────────────────────
  // Local DEMO login — DISABLED by default for production safety.
  //
  // To use during local development only, build with:
  //   flutter run --dart-define=SHOPKEEPER_ENABLE_DEMO_LOGIN=true \
  //              --dart-define=SHOPKEEPER_DEMO_ID=9999999999 \
  //              --dart-define=SHOPKEEPER_DEMO_PASSWORD=demo123
  //
  // `loginWithCredentials()` returns false unless the flag is enabled, so a
  // normal/production build has no working demo backdoor and no stored
  // credentials in the binary.
  // ────────────────────────────────────────────────────────────────────────
  static const bool demoLoginEnabled = bool.fromEnvironment(
    'SHOPKEEPER_ENABLE_DEMO_LOGIN',
    defaultValue: false,
  );

  static const String demoLoginId = String.fromEnvironment(
    'SHOPKEEPER_DEMO_ID',
    defaultValue: '',
  );

  static const String demoLoginPassword = String.fromEnvironment(
    'SHOPKEEPER_DEMO_PASSWORD',
    defaultValue: '',
  );
}
