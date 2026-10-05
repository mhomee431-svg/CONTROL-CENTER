import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/cache/local_cache_service.dart';
import 'package:hyperlocal_app/core/network/api_client.dart';
import 'package:hyperlocal_app/core/storage/local_storage_driver.dart';
import 'package:hyperlocal_app/features/home/data/api_home_repository.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'api_home_repository_pagination_test.mocks.dart';

@GenerateMocks([ApiClient])
void main() {
  group('shops by pin code pagination', () {
    late MockApiClient api;
    late ApiHomeRepository repo;

    /// Every `queryParameters` map the code under test actually sent.
    ///
    /// Recorded inside the stub rather than via `verify(captureAny)`: capturing
    /// the path as well interleaves strings into `.captured` and shifts the
    /// cast, which is a confusing way to lose an assertion.
    final sentParams = <Map<String, dynamic>>[];

    setUp(() {
      sentParams.clear();
      api = MockApiClient();
      repo = ApiHomeRepository(api, LocalCacheService(InMemoryStorageDriver()));
    });

    /// Serves exactly the rows the request asked for, so a client that forgets
    /// to page shows up as a short first page rather than being hidden by a fat
    /// stub that always returns everything.
    void serveShops(int total) {
      // `requiresAuth` must be matched too, or Mockito reports MissingStub.
      when(
        api.get(
          any,
          queryParameters: anyNamed('queryParameters'),
          requiresAuth: anyNamed('requiresAuth'),
        ),
      ).thenAnswer((invocation) async {
        final q =
            invocation.namedArguments[#queryParameters] as Map<String, dynamic>;
        sentParams.add(Map<String, dynamic>.from(q));

        final page = (q['page'] as int?) ?? 1;
        final limit = (q['limit'] as int?) ?? total;
        final all = List.generate(
          total,
          (i) => {
            'id': 'shop-$i',
            'name': 'Shop $i',
            // Keys must match `Shop.fromJson` exactly: imageUrl / isVerified.
            'imageUrl': '',
            'distance': i.toDouble(),
            'rating': 4.0,
            'isVerified': true,
          },
        );
        final start = (page - 1) * limit;
        if (start >= all.length) return {'shops': <dynamic>[]};
        final end = (start + limit).clamp(0, all.length);
        return {'shops': all.sublist(start, end)};
      });
    }

    List<Map<String, dynamic>> sentQueryParams() => sentParams;

    // The endpoint used to take only a pincode and return every match, so one
    // request could materialise an entire area's catalogue. These pin the
    // paged contract that replaced it.
    test('sends page and limit on every request', () async {
      serveShops(5);

      await repo.fetchShopsByPincode('110001', limit: 2);
      await repo.fetchShopsByPincode('110001', page: 2, limit: 2);

      final sent = sentQueryParams();
      expect(sent, hasLength(2));
      for (final query in sent) {
        expect(
          query['limit'],
          2,
          reason: 'every request must be bounded, never "give me everything"',
        );
        expect(query['pincode'], '110001');
      }
      expect(sent[0]['page'], 1);
      expect(sent[1]['page'], 2);
    });

    test('pages do not overlap and together cover every shop', () async {
      serveShops(5);

      final first = await repo.fetchShopsByPincode('110001', limit: 2);
      final second = await repo.fetchShopsByPincode(
        '110001',
        page: 2,
        limit: 2,
      );
      final third = await repo.fetchShopsByPincode('110001', page: 3, limit: 2);

      expect(first.shops, hasLength(2));
      expect(second.shops, hasLength(2));
      expect(third.shops, hasLength(1));

      // Exactly once each: no duplicates, nothing skipped.
      final ids = [
        ...first.shops.map((s) => s.id),
        ...second.shops.map((s) => s.id),
        ...third.shops.map((s) => s.id),
      ];
      expect(ids, hasLength(5));
      expect(ids.toSet(), hasLength(5));
    });

    test('a full page reports hasMore; a short page reports the end', () async {
      serveShops(3);

      // 3 shops at limit 2: the first page is full, so more exist.
      final full = await repo.fetchShopsByPincode('110001', limit: 2);
      expect(full.shops, hasLength(2));
      expect(full.hasMore, isTrue);

      // The next page is short (1 row), so the list is exhausted.
      final short = await repo.fetchShopsByPincode('110001', page: 2, limit: 2);
      expect(short.shops, hasLength(1));
      expect(short.hasMore, isFalse);
    });

    test('an empty response is the end, not a further page', () async {
      serveShops(0);

      final page = await repo.fetchShopsByPincode('999999', limit: 20);
      expect(page.shops, isEmpty);
      expect(page.hasMore, isFalse);
    });
  });
}
