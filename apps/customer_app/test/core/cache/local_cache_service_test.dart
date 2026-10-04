import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/cache/local_cache_service.dart';
import 'package:hyperlocal_app/core/storage/local_storage_driver.dart';

void main() {
  group('LocalCacheService - offline / stale-while-revalidate (Phase 28)', () {
    late LocalCacheService cache;
    late InMemoryStorageDriver storage;

    setUp(() {
      storage = InMemoryStorageDriver();
      cache = LocalCacheService(storage);
    });

    test(
      'returns null when there is no cached entry (cold start, no network)',
      () async {
        final result = await cache.get('shop_123');
        expect(result, isNull);
      },
    );

    test('serves stale data when the network is down — the cache is the source of '
        'truth while offline (stale-but-useful, never hard-expired)', () async {
      // Seed the cache as if a fetch had happened 30 minutes ago: stale vs the
      // 15-minute staleDuration but well under the 2h maxAge.
      final staleAt = DateTime.now()
          .subtract(const Duration(minutes: 30))
          .toIso8601String();
      await storage.setString(
        'cache_v1_shop_123',
        '{"data":"stale-shop-data","cached_at":"$staleAt"}',
      );

      final result = await cache.get('shop_123');
      expect(result, isNotNull);
      expect(result!.data, 'stale-shop-data');
      expect(result.isStale, isTrue);
    });

    test(
      'hard-expired entries are evicted (older than maxAge) so the app stops '
      'showing dangerously stale inventory',
      () async {
        final oldCachedAt = DateTime.now()
            .subtract(const Duration(hours: 3)) // beyond maxAge (2h)
            .toIso8601String();
        await storage.setString(
          'cache_v1_shop_456',
          '{"data":"very-stale-data","cached_at":"$oldCachedAt"}',
        );

        final result = await cache.get('shop_456');
        expect(result, isNull); // hard-expired -> evicts + returns null
        expect(await storage.getString('cache_v1_shop_456'), isNull);
      },
    );

    test('put then get round-trips fresh data (online path)', () async {
      await cache.put('search_papad', {
        'results': [1, 2, 3],
      });
      final result = await cache.get('search_papad');
      expect(result, isNotNull);
      expect(result!.isStale, isFalse);
      expect(result.data['results'], [1, 2, 3]);
    });

    test('corrupted cache payload is evicted and returns null rather than crashing', () async {
      await storage.setString('cache_v1_broken', 'this is not json');
      final result = await cache.get('broken');
      expect(result, isNull);
      expect(await storage.getString('cache_v1_broken'), isNull);
    });

    test('remove clears a single key', () async {
      await cache.put('a', 1);
      await cache.put('b', 2);
      await cache.remove('a');
      expect(await cache.get('a'), isNull);
      expect((await cache.get('b'))!.data, 2);
    });

    test('clear wipes all cached entries', () async {
      await cache.put('a', 1);
      await cache.put('b', 2);
      await cache.clear();
      expect(await cache.get('a'), isNull);
      expect(await cache.get('b'), isNull);
    });

    test('clear leaves data it does not own alone', () async {
      // THE regression this locks. `clear()` used to call `_storage.clear()`,
      // which wiped EVERY SharedPreferences key — so evicting a cache silently
      // destroyed the customer's theme, language, analytics switches, onboarding
      // flag and saved items. A cache clear must only ever touch its own slice.
      await storage.setString('theme_mode', 'dark');
      await storage.setString('saved_products_v1', '["milk"]');
      await storage.setString('has_onboarded', 'true');

      await cache.put('a', 1);
      await cache.clear();

      expect(await cache.get('a'), isNull, reason: 'cache entry is evicted');
      expect(
        await storage.getString('theme_mode'),
        'dark',
        reason: 'theme is not the cache business',
      );
      expect(
        await storage.getString('saved_products_v1'),
        '["milk"]',
        reason: 'saved items must survive a cache clear',
      );
      expect(
        await storage.getString('has_onboarded'),
        'true',
        reason: 'onboarding must survive a cache clear',
      );
    });

    test('cache keys are namespaced so they can be told apart', () async {
      // The prefix is what makes the selective eviction above possible at all.
      await cache.put('home_feed', 1);
      final keys = await storage.keys();
      expect(keys.where((k) => k.startsWith('cache_v1_')), hasLength(1));
      expect(keys, contains('cache_v1_home_feed'));
    });
  });
}
