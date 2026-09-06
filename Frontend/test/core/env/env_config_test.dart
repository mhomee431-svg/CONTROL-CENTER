import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_customer_app/core/env/env_config.dart';

void main() {
  group('EnvConfig defaults', () {
    test('development default base URL is the local backend', () {
      expect(
        EnvConfig.defaultBaseUrlFor(AppEnv.development),
        'http://localhost:8000',
      );
    });

    test('staging default base URL is HTTPS', () {
      expect(
        EnvConfig.defaultBaseUrlFor(AppEnv.staging),
        'https://staging-api.hyperlocal.in',
      );
    });

    test('production default base URL is the production API over HTTPS', () {
      expect(
        EnvConfig.defaultBaseUrlFor(AppEnv.production),
        'https://api.hyperlocal.in',
      );
    });
  });

  group('EnvConfig.normalizeBaseUrl', () {
    test('trims whitespace and trailing slashes', () {
      expect(EnvConfig.normalizeBaseUrl('  https://api.hyperlocal.in/// '),
          'https://api.hyperlocal.in');
    });

    test('strips a stray /v1 suffix', () {
      expect(
        EnvConfig.normalizeBaseUrl('https://api.hyperlocal.in/v1'),
        'https://api.hyperlocal.in',
      );
    });

    test('strips a stray /api/v1 suffix', () {
      expect(
        EnvConfig.normalizeBaseUrl('https://api.hyperlocal.in/api/v1'),
        'https://api.hyperlocal.in',
      );
    });

    test('keeps a bare host untouched', () {
      expect(
        EnvConfig.normalizeBaseUrl('http://10.0.2.2:8000'),
        'http://10.0.2.2:8000',
      );
    });
  });

  group('EnvConfig.validateBaseUrl', () {
    test('accepts HTTPS for production', () {
      expect(
        () => EnvConfig.validateBaseUrl(
          environment: AppEnv.production,
          baseUrl: 'https://api.hyperlocal.in',
        ),
        returnsNormally,
      );
    });

    test('rejects plain HTTP for production', () {
      expect(
        () => EnvConfig.validateBaseUrl(
          environment: AppEnv.production,
          baseUrl: 'http://localhost:8000',
        ),
        throwsStateError,
      );
    });

    test('rejects empty base URL for production', () {
      expect(
        () => EnvConfig.validateBaseUrl(
          environment: AppEnv.production,
          baseUrl: '',
        ),
        throwsStateError,
      );
    });

    test('rejects plain HTTP for staging', () {
      expect(
        () => EnvConfig.validateBaseUrl(
          environment: AppEnv.staging,
          baseUrl: 'http://staging-api.hyperlocal.in',
        ),
        throwsStateError,
      );
    });

    test('accepts plain HTTP for development', () {
      expect(
        () => EnvConfig.validateBaseUrl(
          environment: AppEnv.development,
          baseUrl: 'http://localhost:8000',
        ),
        returnsNormally,
      );
    });
  });

  group('EnvConfig hasApiBaseUrl', () {
    test('dev build without explicit URL reports no backend (mock mode)', () {
      // Compile-time constants in a plain `flutter test` run: not release,
      // no APP_ENV variable → development, and no API_BASE_URL → false.
      expect(EnvConfig.hasApiBaseUrl, isFalse);
    });
  });
}