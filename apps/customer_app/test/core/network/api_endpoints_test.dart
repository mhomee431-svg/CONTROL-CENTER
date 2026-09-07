import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_customer_app/core/network/api_endpoints.dart';

void main() {
  group('ApiEndpoints.apiVersionPrefix', () {
    test('matches the backend FastAPI prefix', () {
      expect(ApiEndpoints.apiVersionPrefix, '/api/v1');
    });
  });

  group('ApiEndpoints.apiPath', () {
    test('prepends the version prefix to a relative endpoint', () {
      expect(ApiEndpoints.apiPath('/auth/send-otp'), '/api/v1/auth/send-otp');
      expect(
        ApiEndpoints.apiPath('/search/v2/products'),
        '/api/v1/search/v2/products',
      );
    });

    test('does not double-prefix an already versioned path', () {
      expect(ApiEndpoints.apiPath('/api/v1/home/feed'), '/api/v1/home/feed');
    });

    test('leaves absolute URLs untouched (e.g. presigned S3)', () {
      expect(
        ApiEndpoints.apiPath(
          'https://bucket.s3.amazonaws.com/upload?X-Amz-Signature=abc',
        ),
        'https://bucket.s3.amazonaws.com/upload?X-Amz-Signature=abc',
      );
    });

    test('adds a leading slash when missing', () {
      expect(ApiEndpoints.apiPath('categories'), '/api/v1/categories');
    });
  });

  group('ApiEndpoints endpoints', () {
    test('all endpoint paths are bare relative (client applies the prefix)', () {
      expect(ApiEndpoints.sendOtp, '/auth/send-otp');
      expect(ApiEndpoints.refreshToken, '/auth/refresh');
      expect(ApiEndpoints.savedProducts, '/saved-products');
      expect(ApiEndpoints.searchProducts, '/search/v2/products');
    });

    test('parameterised endpoints stay bare relative too', () {
      expect(ApiEndpoints.product('p1'), '/products/p1');
      expect(ApiEndpoints.savedProduct('p1'), '/saved-products/p1');
      expect(ApiEndpoints.inventoryByShop('s1'), '/inventory/shop/s1');
      expect(ApiEndpoints.notificationRead('n1'), '/notifications/n1/read');
      expect(
        ApiEndpoints.unregisterDeviceToken('tok'),
        '/notifications/device-token/tok',
      );
    });

    test('versioned path round-trips through apiPath once', () {
      for (final path in [
        ApiEndpoints.sendOtp,
        ApiEndpoints.product('p1'),
        ApiEndpoints.savedProduct('p1'),
        ApiEndpoints.notificationRead('n1'),
      ]) {
        expect(ApiEndpoints.apiPath(path), '/api/v1$path');
      }
    });
  });
}