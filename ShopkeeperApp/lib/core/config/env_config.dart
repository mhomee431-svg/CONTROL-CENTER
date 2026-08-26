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
  // TEMP/DEV HARDCODED LOGIN CREDENTIALS — remove before release.
  //
  // Lets you sign in from the LoginScreen WITHOUT the OTP/backend flow.
  // Enter this phone number as the ID and this password, and the app opens
  // a local demo session straight into the dashboard.
  // To remove later: delete these two constants, the Password field in
  // login_screen.dart, and loginWithCredentials()/skipLogin() +
  // `isGuest` in auth_controller.dart.
  // ────────────────────────────────────────────────────────────────────────
  static const String demoLoginId = '9999999999';
  static const String demoLoginPassword = 'demo123';
}
