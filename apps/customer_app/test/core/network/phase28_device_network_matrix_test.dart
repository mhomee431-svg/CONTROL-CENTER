import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/cache/local_cache_service.dart';
import 'package:hyperlocal_app/core/storage/local_storage_driver.dart';
import 'package:hyperlocal_app/features/directions/data/device_location_service.dart';
import 'package:hyperlocal_app/features/directions/domain/models/location_models.dart';

/// Phase 28 — real-device E2E (network / GPS / permission matrix).
///
/// This workspace has no physical Android device or emulator, so the
/// device-only legs of the charter are expressed as deterministic unit tests
/// against the REAL production classes (no test-only stubs in lib/):
///
///   * [DeviceLocationService] carries in-memory GPS/permission flags for
///     debug/test builds (its `_useRealGps` is gated on `EnvConfig.isProduction`,
///     which is false under `flutter test`), so the GPS-disabled and
///     permission-denied paths can be exercised deterministically.
///   * [LocalCacheService] is the offline first-stop: when the network is down
///     the UI reads stale-but-useful cache instead of a blank screen.
///
/// Map these test scenarios to a real handset with the Phase-28 protocol in
/// docs/PHASE28_REAL_DEVICE_E2E_TEST.md.
void main() {
  group('Phase 28 GPS matrix', () {
    late DeviceLocationService service;

    setUp(() {
      service = DeviceLocationService();
      service.setMockGpsEnabled(true);
      service.setMockPermissionGranted(true);
    });

    test(
      'GPS disabled -> isGpsEnabled false and getCurrentLocation throws noGps',
      () async {
        service.setMockGpsEnabled(false);
        expect(await service.isGpsEnabled(), isFalse);
        expect(await service.requestPermission(), isTrue);
        expect(
          () => service.getCurrentLocation(),
          throwsA(
            isA<LocationException>().having(
              (e) => e.type,
              'type',
              LocationErrorType.noGps,
            ),
          ),
        );
      },
    );
  });

  group('Phase 28 permission matrix', () {
    late DeviceLocationService service;

    setUp(() {
      service = DeviceLocationService();
      service.setMockGpsEnabled(true);
      service.setMockPermissionGranted(true);
    });

    test(
      'permission denied throws LocationException(permissionDenied)',
      () async {
        service.setMockPermissionGranted(false);
        expect(await service.requestPermission(), isFalse);
        expect(
          () => service.getCurrentLocation(),
          throwsA(
            isA<LocationException>().having(
              (e) => e.type,
              'type',
              LocationErrorType.permissionDenied,
            ),
          ),
        );
      },
    );

    test(
      'GPS on + permission granted returns the mock coordinate (Delhi)',
      () async {
        final loc = await service.getCurrentLocation();
        expect(loc.latitude, closeTo(28.7041, 1e-4));
        expect(loc.longitude, closeTo(77.1025, 1e-4));
      },
    );

    test(
      'calculateDistance matches the great-circle distance (Patna -> Delhi)',
      () {
        const patna = Coordinates(25.5941, 85.1376);
        const delhi = Coordinates(28.7041, 77.1025);
        final km = service.calculateDistance(patna, delhi);
        expect(km, greaterThan(800));
        expect(km, lessThan(950));
      },
    );
  });

  group('Phase 28 offline cache fallback (no network)', () {
    // Inject a real InMemoryStorageDriver so the cache test stays deterministic
    // and never touches shared_preferences (which needs a plugin binding).
    late InMemoryStorageDriver storage;
    late LocalCacheService cache;

    setUp(() {
      storage = InMemoryStorageDriver();
      cache = LocalCacheService(storage);
    });

    test('serves stale data when the network is down (stale-but-useful)', () async {
      final staleAt = DateTime.now()
          .subtract(const Duration(minutes: 30))
          .toIso8601String();
      await storage.setString(
        'cache_v1_product_789',
        '{"data":{"id":789,"price":42.0,"available":true},"cached_at":"$staleAt"}',
      );

      final result = await cache.get('product_789');
      expect(result, isNotNull);
      expect(result!.isStale, isTrue);
      expect(result.data['price'], 42.0);
      expect(result.data['available'], true);
    });

    test(
      'hard-expired cache (offline too long) returns null and is evicted',
      () async {
        final staleAt = DateTime.now()
            .subtract(const Duration(hours: 3))
            .toIso8601String();
        await storage.setString(
          'cache_v1_shop_1',
          '{"data":{"id":1},"cached_at":"$staleAt"}',
        );

        final result = await cache.get('shop_1');
        expect(result, isNull); // evicted past maxAge (2h)
        expect(await storage.getString('cache_v1_shop_1'), isNull);
      },
    );

    test('fresh cache is not stale and round-trips data', () async {
      await cache.put('search_papad', {
        'results': [1, 2, 3],
      });
      final result = await cache.get('search_papad');
      expect(result, isNotNull);
      expect(result!.isStale, isFalse);
      expect(result.data['results'], [1, 2, 3]);
    });

    test('corrupted cache entry is evicted and returns null', () async {
      await storage.setString('cache_v1_broken', 'not-json');
      final result = await cache.get('broken');
      expect(result, isNull);
      expect(await storage.getString('cache_v1_broken'), isNull);
    });
  });
}
