/// Environment configuration for the Shopkeeper App.
///
/// Three supported environments, selected at build time:
///
/// | Environment | Selection | Default base URL |
/// |---|---|---|
/// | development (Android emulator → host) | (auto when not release) | `http://10.0.2.2:8000` |
/// | staging | `--dart-define=APP_ENV=staging` | `https://staging-api.hyperlocal.in` |
/// | production (default release) | `--dart-define=APP_ENV=production` or AOT release | `https://api.hyperlocal.in` |
///
/// The deploying pipeline injects the final base URL at build time:
///
/// ```bash
/// flutter build apk --release \
///   --dart-define=SHOPKEEPER_API_BASE_URL=https://api.hyperlocal.in
/// ```
///
/// `SHOPKEEPER_API_BASE_URL` must be **scheme + host only** — the versioned
/// `/api/v1` prefix already lives in `ApiEndpoints`. A stray trailing
/// `/v1`/`/api/v1` is stripped automatically. Never embed production secrets
/// here.
class EnvConfig {
  EnvConfig._();

  /// Build-time override injected by CI (`--dart-define=SHOPKEEPER_API_BASE_URL=...`).
  static const String _explicitApiBaseUrl = String.fromEnvironment(
    'SHOPKEEPER_API_BASE_URL',
  );

  /// Explicit environment selector (`--dart-define=APP_ENV=staging` etc.).
  static const String _explicitEnvironment = String.fromEnvironment(
    'APP_ENV',
  );

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

  /// Backend base URL — scheme + host only. Resolution order:
  ///   1. Development runtime auto-discovery result (DevBackendDiscovery)
  ///   2. Explicit `--dart-define=SHOPKEEPER_API_BASE_URL=…` override
  ///   3. The environment's default
  static String get apiBaseUrl {
    final runtime = runtimeApiBaseUrlOverride;
    final url = runtime?.isNotEmpty == true
        ? runtime!
        : _explicitApiBaseUrl.isNotEmpty
            ? _explicitApiBaseUrl
            : defaultBaseUrlFor(environment);
    return normalizeBaseUrl(url);
  }

  /// The build-time explicit override (`--dart-define`), exposed for the
  /// development auto-discovery logic to know when it must NOT run.
  static String get explicitApiBaseUrl => _explicitApiBaseUrl;

  /// Set at startup by [DevBackendDiscovery.discover] in development builds.
  /// Ignored in production (discovery never runs there).
  static String? runtimeApiBaseUrlOverride;

  /// Whether this is a production build.
  static bool get isProduction => environment == AppEnv.production;

  /// Whether the app is running in AOT release mode.
  static bool get isRelease => _isRelease;

  /// Default base URL for an environment (scheme + host only; endpoint paths
  /// already carry the `/api/v1` version prefix).
  static String defaultBaseUrlFor(AppEnv env) {
    return switch (env) {
      AppEnv.production => 'https://api.hyperlocal.in',
      AppEnv.staging => 'https://staging-api.hyperlocal.in',
      // Dev-only default — plain HTTP host-local backend; never ships in release.
      AppEnv.development => 'http://10.0.2.2:8000',
    };
  }

  /// Removes surrounding whitespace/trailing slashes and strips a stray API
  /// version suffix (`…/v1` or `…/api/v1`) so the base URL never
  /// double-prefixes with the endpoint paths.
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
  /// (host-local dev backend only).
  static void validateBaseUrl({
    required AppEnv environment,
    required String baseUrl,
  }) {
    final isHttps = baseUrl.startsWith('https://');
    final schemeOk = (environment == AppEnv.production ||
            environment == AppEnv.staging)
        ? isHttps
        : true;
    if (!schemeOk || baseUrl.isEmpty) {
      throw StateError(
        'Invalid $environment API base URL: "$baseUrl" — production/staging builds must use HTTPS.',
      );
    }
  }

  /// Fails fast at startup when a production build is misconfigured.
  /// Called from [main].
  static void validateProduction() =>
      validateBaseUrl(environment: environment, baseUrl: apiBaseUrl);

  static const bool useMockData = bool.fromEnvironment(
    'SHOPKEEPER_USE_MOCK',
    defaultValue: false,
  );
}

/// The environment the app is built for.
enum AppEnv { development, staging, production }
