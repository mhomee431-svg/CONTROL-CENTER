import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/features/search/domain/models/search_models.dart';
import 'package:hyperlocal_app/features/search/domain/search_repository.dart';
import 'package:hyperlocal_app/features/search/domain/search_state.dart';
import 'package:hyperlocal_app/features/search/presentation/controllers/search_controller.dart';

/// A repository whose `searchProducts` calls can each be parked and released by
/// hand, in any order the test chooses.
///
/// The gate is the entire point. A repository that answered immediately would
/// let every request finish before the next one started, so the interleaving
/// that causes a stale overwrite could never be observed at all.
class _GatedRepository implements SearchRepository {
  /// One completer per in-flight call, oldest first.
  final List<Completer<List<ShopProductResult>>> gates = [];

  /// How many `searchProducts` calls have been made.
  int callCount = 0;

  /// When false every call answers immediately (used by the refresh tests).
  bool holdOpen = true;

  /// Lets the test settle the microtask queue after kicking off a call.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  @override
  Future<List<ShopProductResult>> searchProducts({
    required String query,
    required int page,
    required int limit,
    SortOption sort = SortOption.nearest,
    Map<String, dynamic>? filters,
    double? latitude,
    double? longitude,
  }) {
    callCount++;
    if (!holdOpen) return Future.value(_rows('$query p$page', limit));
    final gate = Completer<List<ShopProductResult>>();
    gates.add(gate);
    return gate.future;
  }

  /// Completes the oldest still-open request with rows labelled [label].
  void releaseOldest(String label, {int limit = 10}) {
    gates.removeAt(0).complete(_rows(label, limit));
  }

  /// Fails the oldest still-open request.
  void failOldest(Object error) => gates.removeAt(0).completeError(error);

  /// Rows whose product name carries [label], so a test can tell which request
  /// actually produced what is on screen.
  List<ShopProductResult> _rows(String label, int limit) => List.generate(
    limit,
    (i) => ShopProductResult(
      id: '$label-$i',
      productId: 'p_$label$i',
      productName: '$label row $i',
      productImageUrl: '',
      shopId: 's$i',
      shopName: 'Shop $i',
      price: 10.0 + i,
      isAvailable: true,
      distanceInKm: 1,
      shopRating: 4,
      lastUpdated: DateTime(2026, 1, 1),
      availability: InventoryAvailability.inStock,
      freshness: FreshnessLevel.fresh,
    ),
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

ProviderContainer _boot(_GatedRepository repo) {
  final container = ProviderContainer(
    overrides: [searchRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('a superseded search response is discarded', () {
    test('a sort change makes the earlier request stale', () async {
      final repo = _GatedRepository();
      final container = _boot(repo);

      // The relevance search goes in flight first and stays open.
      container.read(searchResultsProvider('milk'));
      await repo.settle();
      expect(repo.gates.length, 1);

      // The customer switches sort while it is still loading.
      final controller = container.read(searchResultsProvider('milk').notifier);
      controller.updateSort(SortOption.lowestPrice);
      await repo.settle();
      expect(repo.gates.length, 2);

      // The OLD request now answers, and it is the last thing to arrive.
      repo.releaseOldest('relevance');
      await repo.settle();

      final state = container.read(searchResultsProvider('milk'));
      expect(
        state.stage,
        SearchStage.loading,
        reason: 'the stale relevance response must not write state',
      );
      expect(state.results, isEmpty);

      // Only when the newer request answers does the screen change.
      repo.releaseOldest('price');
      await repo.settle();
      final settled = container.read(searchResultsProvider('milk'));
      expect(settled.stage, SearchStage.results);
      expect(settled.results.first.productName, startsWith('price'));
    });

    test(
      'a late failure from a stale request does not show an error',
      () async {
        final repo = _GatedRepository();
        final container = _boot(repo);

        container.read(searchResultsProvider('milk'));
        await repo.settle();
        final controller = container.read(
          searchResultsProvider('milk').notifier,
        );
        controller.updateFilters({'in_stock': true});
        await repo.settle();

        // The superseded request fails while the good one is still in flight.
        repo.failOldest(Exception('stale network error'));
        await repo.settle();

        expect(
          container.read(searchResultsProvider('milk')).stage,
          SearchStage.loading,
          reason: 'a stale error must not replace the current results',
        );

        repo.releaseOldest('filtered');
        await repo.settle();
        final state = container.read(searchResultsProvider('milk'));
        expect(state.stage, SearchStage.results);
        expect(state.error, isNull);
      },
    );

    test('a page request open when refresh starts is thrown away', () async {
      final repo = _GatedRepository();
      final container = _boot(repo);

      container.read(searchResultsProvider('dove'));
      await repo.settle();
      repo.releaseOldest('page1');
      await repo.settle();

      final controller = container.read(searchResultsProvider('dove').notifier);
      // A scroll opens a page-2 request...
      final pendingPage = controller.fetchNextPage();
      await repo.settle();
      expect(repo.gates.length, 1);

      // ...and then the customer pulls to refresh.
      final refresh = controller.refresh();
      await repo.settle();

      // The abandoned page-2 response arrives and must be ignored.
      repo.releaseOldest('stale-page2');
      await repo.settle();
      await pendingPage;

      var state = container.read(searchResultsProvider('dove'));
      expect(state.currentPage, 1);
      expect(
        state.results.every((r) => r.productName.startsWith('page1')),
        isTrue,
        reason: 'page-2 rows belong to a result set that no longer exists',
      );

      // Now let the refresh's own request answer; those are the rows that stay.
      repo.releaseOldest('fresh-page1');
      await refresh;
      state = container.read(searchResultsProvider('dove'));
      expect(state.results.first.productName, startsWith('fresh-page1'));
      expect(state.currentPage, 1);
    });
    test('cancelling discards a response still in flight', () async {
      final repo = _GatedRepository();
      final container = _boot(repo);

      container.read(searchResultsProvider('dove'));
      await repo.settle();
      expect(repo.gates.length, 1);

      // The customer backs out of the search before it answers.
      container.read(searchResultsProvider('dove').notifier).cancel();
      await repo.settle();

      repo.releaseOldest('too-late');
      await repo.settle();

      final state = container.read(searchResultsProvider('dove'));
      expect(state.stage.name, 'idle');
      expect(
        state.results,
        isEmpty,
        reason: 'a cancelled search must not repopulate itself',
      );
    });
  });

  group('refresh', () {
    test('re-runs the search and keeps the chosen sort and filters', () async {
      final repo = _GatedRepository()..holdOpen = false;
      final container = _boot(repo);

      container.read(searchResultsProvider('dove'));
      await repo.settle();

      final controller = container.read(searchResultsProvider('dove').notifier);
      controller.updateSort(SortOption.lowestPrice);
      await repo.settle();
      controller.updateFilters({'in_stock': true});
      await repo.settle();

      final callsBefore = repo.callCount;
      await controller.refresh();

      expect(repo.callCount, callsBefore + 1);
      final state = container.read(searchResultsProvider('dove'));
      expect(state.sort, SortOption.lowestPrice);
      expect(state.filters['in_stock'], true);
      expect(state.currentPage, 1);
      expect(state.results, isNotEmpty);
    });

    test(
      'returns only after fresh rows have replaced the stale ones',
      () async {
        final repo = _GatedRepository()..holdOpen = false;
        final container = _boot(repo);

        container.read(searchResultsProvider('dove'));
        await repo.settle();
        final controller = container.read(
          searchResultsProvider('dove').notifier,
        );

        var completed = false;
        final future = controller.refresh().then((_) => completed = true);
        expect(
          completed,
          isFalse,
          reason: 'RefreshIndicator must keep spinning until rows are in',
        );
        await future;
        expect(completed, isTrue);
        expect(
          container.read(searchResultsProvider('dove')).stage,
          SearchStage.results,
        );
      },
    );
  });
}
