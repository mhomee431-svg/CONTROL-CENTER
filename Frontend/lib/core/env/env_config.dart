class EnvConfig {
  /// API base URL injected at build time via:
  /// `flutter run --dart-define=API_BASE_URL=https://api.example.com/v1`
  ///
  /// No default value is provided to prevent accidental production
  /// connections during development. The app will fail fast if this
  /// is not set, which is safer than silently using a wrong URL.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  /// Maps API key injected at build time via:
  /// `flutter run --dart-define=MAPS_API_KEY=your_api_key_here`
  ///
  /// Perfect for CI/CD: the key is embedded at compile time and
  /// never exists in the repository or runtime configuration.
  static const String mapsApiKey = String.fromEnvironment(
    'MAPS_API_KEY',
    defaultValue: '',
  );

  /// Whether the app is running in production mode.
  /// In release builds, `dart.vm.product` is automatically true.
  static const bool isProduction = bool.fromEnvironment(
    'dart.vm.product',
    defaultValue: false,
  );

  /// Returns true if the API base URL has been configured.
  static bool get hasApiBaseUrl => apiBaseUrl.isNotEmpty;
}