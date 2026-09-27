/// Environment profiles for the customer Flutter app.
///
/// Three supported environments, selected at build time:
///
/// | Environment | Selection | Default base URL |
/// |---|---|---|
/// | development (default debug/test) | (auto when not release) | `http://localhost:8000` |
/// | staging | `--dart-define=APP_ENV=staging` | `https://staging-api.hyperlocal.in` |
/// | production (default release) | `--dart-define=APP_ENV=production` or AOT release | `https://api.hyperlocal.in` |
///
/// The deploying pipeline normally injects the final base URL at build time:
///
/// ```bash
/// flutter build apk --release \
///   --dart-define=API_BASE_URL=https://api.hyperlocal.in \
///   --dart-define=MAPS_API_KEY=...
/// ```
///
/// `API_BASE_URL` must be **scheme + host only** (no `/api/v1` suffix — the app
/// appends the API version prefix centrally; see `ApiEndpoints.apiVersionPrefix`).
///
/// `APP_ENV` is a deliberate escape hatch for staging/local builds; in a
/// release build the environment defaults to `production`, so an unconfigured
/// release can never silently fall back to a mock or a localhost endpoint.
class EnvConfig {
  EnvConfig._();

  /// Build-time override injected by CI (`--dart-define=API_BASE_URL=...`).
  static const String _explicitApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
  );

  /// Explicit environment selector (`--dart-define=APP_ENV=staging` etc.).
  static const String _explicitEnvironment = String.fromEnvironment('APP_ENV');

  /// True in AOT release builds (`flutter build apk --release`...).
  static const bool _isRelease = bool.fromEnvironment(
    'dart.vm.product',
    defaultValue: false,
  );

  /// Active environment: release builds default to production; debug and
  /// test runs default to development.
  static AppEnv get environment {
    return switch (_explicitEnvironment) {
      'staging' => AppEnv.staging,
      'production' => AppEnv.production,
      'development' => AppEnv.development,
      _ => _isRelease ? AppEnv.production : AppEnv.development,
    };
  }

  /// API base URL — scheme + host (NO API version path; the version prefix is
  /// prepended centrally by the API client.). An explicit `API_BASE_URL` always
  /// wins; otherwise the environment's default is used.
  static String get apiBaseUrl {
    final url = _explicitApiBaseUrl.isNotEmpty
        ? _explicitApiBaseUrl
        : defaultBaseUrlFor(environment);
    return normalizeBaseUrl(url);
  }

  /// Whether a real backend is selected for this build. Always true for
  /// staging/production builds; development only when an explicit
  /// `API_BASE_URL` is provided — so an unconfigured debug run keeps using
  /// the local mocks exactly as before.
  static bool get hasApiBaseUrl =>
      environment != AppEnv.development || _explicitApiBaseUrl.isNotEmpty;

  /// Whether this is a production build. Used to gate mocks off and force
  /// real device/network providers in release.
  static bool get isProduction => environment == AppEnv.production;

  /// Whether the app is running in AOT release mode.
  static bool get isRelease => _isRelease;

  /// Default base URL for an environment (scheme + host only; version prefix
  /// is appended centrally by the API client).
  static String defaultBaseUrlFor(AppEnv env) {
    return switch (env) {
      AppEnv.production => 'https://api.hyperlocal.in',
      AppEnv.staging => 'https://staging-api.hyperlocal.in',
      // Dev-only default — plain HTTP local backend; never ships in release.
      AppEnv.development => 'http://localhost:8000',
    };
  }

  /// Removes surrounding whitespace/trailing slashes and strips a stray API
  /// version suffix (`…/v1` or `…/api/v1`) so the base URL never
  /// double-prefixes with the centrally-appended version.
  static String normalizeBaseUrl(String url) {
    var result = url.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    if (result.endsWith('/api/v1')) {
      result = result.substring(0, result.length - '/api/v1'.length);
    } else if (result.endsWith('/v1')) {
      result = result.substring(0, result.length - '/v1'.length);
    }
    return result;
  }

  /// Throws if the given base URL is invalid for the given environment.
  /// Production and staging must use HTTPS; development may use plain HTTP
  /// (localhost dev backend only).
  static void validateBaseUrl({
    required AppEnv environment,
    required String baseUrl,
  }) {
    final isHttps = baseUrl.startsWith('https://');
    final schemeOk =
        (environment == AppEnv.production || environment == AppEnv.staging)
        ? isHttps
        : true;
    if (!schemeOk || baseUrl.isEmpty) {
      throw StateError(
        'Invalid $environment API base URL: "$baseUrl" — production/staging builds must use HTTPS.',
      );
    }
  }

  /// Fails fast at startup when a production build is misconfigured (e.g. an
  /// `http://` override or an empty/relative base URL). Called from [main].
  static void validateProduction() =>
      validateBaseUrl(environment: environment, baseUrl: apiBaseUrl);

  /// Maps API key injected at build time via:
  /// `flutter run --dart-define=MAPS_API_KEY=your_api_key_here`
  ///
  /// Perfect for CI/CD: the key is embedded at compile time and
  /// never exists in the repository or runtime configuration.
  static const String mapsApiKey = String.fromEnvironment(
    'MAPS_API_KEY',
    defaultValue: '',
  );

  /// Kill switch for the barcode entry point (camera scan + manual lookup):
  /// `flutter run --dart-define=BARCODE_LOOKUP_ENABLED=false`.
  ///
  /// WHY IT IS NEEDED: `barcodeSupportProvider` discovers a missing backend
  /// route by trying it, which means one failing request per app session. When
  /// an operator already KNOWS the deployment has no barcode service, this flag
  /// removes the entry point up front — no wasted request, no dead icon. It
  /// defaults to enabled because barcode search is a real feature wherever the
  /// backend serves it.
  static const bool barcodeLookupEnabled = bool.fromEnvironment(
    'BARCODE_LOOKUP_ENABLED',
    defaultValue: true,
  );
}


/// The environment the app is built for.
enum AppEnv { development, staging, production }
