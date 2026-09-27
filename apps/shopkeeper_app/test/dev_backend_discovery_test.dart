import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/config/dev_backend_discovery.dart';
import 'package:hyperlocal_shopkeeper_app/core/config/env_config.dart';

void main() {
  setUp(() {
    DevBackendDiscovery.resolvedBaseUrl = null;
    EnvConfig.runtimeApiBaseUrlOverride = null;
  });

  tearDown(() {
    DevBackendDiscovery.resolvedBaseUrl = null;
    EnvConfig.runtimeApiBaseUrlOverride = null;
  });

  group('DevBackendDiscovery', () {
    test('reachable candidate is published to EnvConfig (wiring regression)',
        () async {
      // Only the adb-reverse candidate answers /health.
      await DevBackendDiscovery.discover(
        probe: (url) async => url == 'http://127.0.0.1:8000',
      );

      expect(DevBackendDiscovery.resolvedBaseUrl, 'http://127.0.0.1:8000');
      // The regression: resolvedBaseUrl alone was never read by EnvConfig.
      expect(EnvConfig.runtimeApiBaseUrlOverride, 'http://127.0.0.1:8000');
      expect(EnvConfig.apiBaseUrl, 'http://127.0.0.1:8000');
    });

    test('first reachable candidate wins in candidate order', () async {
      await DevBackendDiscovery.discover(
        probe: (url) async => true,
      );

      expect(DevBackendDiscovery.resolvedBaseUrl,
          DevBackendDiscovery.candidates.first);
      expect(EnvConfig.runtimeApiBaseUrlOverride,
          DevBackendDiscovery.candidates.first);
    });

    test('unreachable candidates fall back to the build-time default', () async {
      await DevBackendDiscovery.discover(
        probe: (url) async => false,
      );

      expect(DevBackendDiscovery.resolvedBaseUrl, isNull);
      expect(EnvConfig.runtimeApiBaseUrlOverride, isNull);
      expect(EnvConfig.apiBaseUrl, 'http://10.0.2.2:8000');
    });

    test('a throwing probe does not abort discovery', () async {
      await DevBackendDiscovery.discover(
        probe: (url) async {
          if (url == DevBackendDiscovery.candidates.first) {
            throw Exception('network down');
          }
          return url == 'http://127.0.0.1:8000';
        },
      );

      expect(EnvConfig.runtimeApiBaseUrlOverride, 'http://127.0.0.1:8000');
      expect(EnvConfig.apiBaseUrl, 'http://127.0.0.1:8000');
    });
  });
}