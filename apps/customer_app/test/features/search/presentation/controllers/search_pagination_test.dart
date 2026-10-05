import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_app/features/search/domain/models/search_models.dart';
import 'package:hyperlocal_app/features/search/domain/search_repository.dart';
import 'package:hyperlocal_app/features/search/presentation/controllers/search_controller.dart';

/// A repository whose page fetches can be held open, so a test can fire two
/// `fetchNextPage()` calls while the first is genuinely still in flight.
///
/// The gate is the whole point: without it both calls would run to completion
/// synchronously and the race could never be observed.
class _ControllableRepository implements SearchRepository {
  _ControllableRepository({this.rowsPerPage = 10});

  final int rowsPerPage;

  /// Pages requested, in order. Asserted on to prove nothing was skipped.
  final List<int> requestedPages = [];

  /// When set, every `searchProducts` call parks on it instead of returning,
  /// leaving the caller suspended mid-fetch.
  Completer<void>? gate;

  /// When true, the next call throws, for the retry path.
  bool failNext = false;

  @override
  Future<List<ShopProductResult>> searchProducts({
    required String query,
    required int page,
    required int limit,
    SortOption sort = SortOption.nearest,
    Map<String, dynamic>? filters,
    double? latitude,
    double? longitude,
  }) async {
    requestedPages.add(page);
    final held = gate;
    if (held != null) await held.future;
    if (failNext) throw Exception('network down');
    if (page > 3) return const [];
    return List.generate(rowsPerPage, (i) => _row(page, i), growable: false);
  }

  ShopProductResult _row(int page, int i) => ShopProductResult(
    id: 'r_${page}_$i',
    productId: 'p_${page}_$i',
    productName: 'Page $page row $i',
    productImageUrl: '',
    shopId: 's$page',
    shopName: 'Shop $page',
    price: 100.0 + i,
    isAvailable: true,
    distanceInKm: 1,
    shopRating: 4,
    lastUpdated: DateTime(2026, 1, 1),
    availability: InventoryAvailability.inStock,
    freshness: FreshnessLevel.fresh,
  );

  @override
  Future<List<String>> getPopularSearches() async => const [];

  @override
  Future<List<String>> getRecentSearches() async => const [];

  @override
  Future<List<SearchSuggestion>> getSuggestions(String query) async => const [];

  @override
  Future<List<ShopProductResult>> lookupBarcode(
    String barcode, {
    double? latitude,
    double? longitude,
    int page = 1,
    int limit = 20,
  }) async => const [];
}

void main() {
  group('search result pagination', () {
    /// Builds a container and lets the controller's page-1 fetch finish.
    Future<ProviderContainer> boot(_ControllableRepository repo) async {
      final container = ProviderContainer(
        overrides: [searchRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      // `_fetchInitial` is private and fires from `build()`, so touching the
      // provider is what starts it; the delay lets its await resolve.
      container.read(searchResultsProvider('milk'));
      await Future.delayed(const Duration(milliseconds: 20));
      return container;
    }

    test('two concurrent calls fetch one page -- no duplicate work', () async {
      final repo = _ControllableRepository();
      final container = await boot(repo);
      expect(container.read(searchResultsProvider('milk')).results.length, 10);

      // Hold the next page open and fire twice, as a fling's burst of scroll
      // events would.
      repo.gate = Completer<void>();
      final notifier = container.read(searchResultsProvider('milk').notifier);
      final first = notifier.fetchNextPage();
      final second = notifier.fetchNextPage();

      repo.gate!.complete();
      await Future.wait([first, second]);

      // Only page 2 was ever requested, and the rows are not duplicated.
      //
      // Worth stating plainly: this test was written to catch a race that does
      // not exist. The `isFetchingMore` check and its set are adjacent with no
      // `await` between them, so a second caller always observes the flag.
      // Deleting the guard and re-running this test confirmed both calls still
      // collapsed to one request. The test is kept because it pins the
      // invariant cheaply, not because it once caught a bug.
      expect(repo.requestedPages, [1, 2]);
      expect(container.read(searchResultsProvider('milk')).results.length, 20);
      expect(container.read(searchResultsProvider('milk')).currentPage, 2);
    });

    test('a failed page is retried, not skipped', () async {
      final repo = _ControllableRepository();
      final container = await boot(repo);

      repo.failNext = true;
      await container
          .read(searchResultsProvider('milk').notifier)
          .fetchNextPage();

      final afterFailure = container.read(searchResultsProvider('milk'));
      expect(afterFailure.error, isNotNull);
      // The page that failed never arrived, so its number must be handed back
      // to the next attempt rather than consumed.
      expect(afterFailure.currentPage, 1);

      repo.failNext = false;
      await container
          .read(searchResultsProvider('milk').notifier)
          .fetchNextPage();

      // It asked for page 2 again, not page 3.
      expect(repo.requestedPages, [1, 2, 2]);
      expect(container.read(searchResultsProvider('milk')).results.length, 20);
    });

    test('stops paging once the backend returns a short page', () async {
      // 3 rows against a limit of 10 is a short page: the backend is done.
      final repo = _ControllableRepository(rowsPerPage: 3);
      final container = await boot(repo);

      final state = container.read(searchResultsProvider('milk'));
      expect(state.results.length, 3);
      expect(state.hasReachedMax, isTrue);

      // Further calls must not reach the network.
      await container
          .read(searchResultsProvider('milk').notifier)
          .fetchNextPage();
      expect(repo.requestedPages, [1]);
    });

    test('retained results never exceed the in-memory cap', () async {
      // `searchResultsProvider` is deliberately NOT autoDispose, so the list
      // outlives the screen. This pins the ceiling that stops a long scroll
      // growing that list for the rest of the session.
      final repo = _ControllableRepository();
      final container = await boot(repo);

      final notifier = container.read(searchResultsProvider('milk').notifier);
      // Keep scrolling well past the number of pages the stub can supply.
      for (var i = 0; i < 40; i++) {
        await notifier.fetchNextPage();
      }

      final state = container.read(searchResultsProvider('milk'));
      expect(
        state.results.length,
        lessThanOrEqualTo(500),
        reason: 'results held in memory must stay under the cap',
      );
      // Once the stub runs dry the controller must stop asking.
      expect(state.hasReachedMax, isTrue);
    });
  });
}
