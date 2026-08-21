import 'package:envied/envied.dart';

part 'env.g.dart';

@Envied(path: '.env')
abstract class Env {
  @EnviedField(varName: 'API_BASE_URL', obfuscate: true)
  static final String apiBaseUrl = _Env.apiBaseUrl;

  /// Maps API key injected at build time via:
  /// `flutter run --dart-define=MAPS_API_KEY=your_api_key_here`
  ///
  /// Perfect for CI/CD: the key is embedded at compile time and
  /// never exists in the repository or runtime configuration.
  static const String mapsApiKey = String.fromEnvironment(
    'MAPS_API_KEY',
    defaultValue: '',
  );
}
