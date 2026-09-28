import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyperlocal_app/core/performance/debouncer.dart';
import 'package:hyperlocal_app/features/search/data/mock_search_repository.dart';
import 'package:hyperlocal_app/features/search/domain/models/search_models.dart';
import 'package:hyperlocal_app/features/search/domain/search_event_tracker.dart';
import 'package:hyperlocal_app/features/search/domain/search_repository.dart';
import 'package:hyperlocal_app/features/search/domain/search_state.dart';
import 'package:hyperlocal_app/features/search/presentation/controllers/search_controller.dart';

void main() {
  group('Debouncer', () {
    test('cancels previous timers and only runs the latest action', () async {
      final debouncer = Debouncer(delay: const Duration(milliseconds: 100));
      var callCount = 0;

      debouncer.run(() => callCount++);
      debouncer.run(() => callCount++);
      debouncer.run(() => callCount++);

      await Future.delayed(const Duration(milliseconds: 200));

      expect(callCount, 1);

      debouncer.dispose();
    });

    test('executes action after the debounce period', () async {
      final debouncer = Debouncer(delay: const Duration(milliseconds: 50));
      var executed = false;

      debouncer.run(() => executed = true);

      expect(executed, false);

      await Future.delayed(const Duration(milliseconds: 100));

      expect(executed, true);

      debouncer.dispose();
    });
  });

  group('SearchQueryNotifier', () {
    test('starts in idle stage with empty query', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(searchQueryProvider);
      expect(state.query, '');
      expect(state.stage, SearchStage.idle);
    });

    test('onTextChanged sets typing stage', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(searchQueryProvider.notifier).onTextChanged('par');
      final state = container.read(searchQueryProvider);
      expect(state.query, 'par');
      expect(state.stage, SearchStage.typing);
    });

    test('onTextChanged does not advance the debounced query', () {
      // Suggestion fetches key off [SearchQueryState.debouncedQuery]; raw
      // keystrokes must never trigger them.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(searchQueryProvider.notifier).onTextChanged('para');
      container.read(searchQueryProvider.notifier).onTextChanged('parac');

      final state = container.read(searchQueryProvider);
      expect(state.query, 'parac');
      expect(state.debouncedQuery, '');
    });

    test('debouncedTextChanged advances both query values', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(searchQueryProvider.notifier)
          .debouncedTextChanged('paracetamol');

      final state = container.read(searchQueryProvider);
      expect(state.query, 'paracetamol');
      expect(state.debouncedQuery, 'paracetamol');
      expect(state.stage, SearchStage.typing);
    });

    test('clear resets to idle', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(searchQueryProvider.notifier).onTextChanged('par');
      container.read(searchQueryProvider.notifier).clear();
      final state = container.read(searchQueryProvider);
      expect(state.query, '');
      expect(state.stage, SearchStage.idle);
    });
  });

  group('SearchResultsController', () {
    test(
      'loads initial results and appends next page on fetchNextPage',
      () async {
        final container = ProviderContainer(
          overrides: [
            searchRepositoryProvider.overrideWithValue(MockSearchRepository()),
          ],
        );
        addTearDown(container.dispose);

        final provider = searchResultsProvider('Paracetamol');
        final controller = container.read(provider.notifier);

        await Future.delayed(const Duration(milliseconds: 900));

        var state = container.read(provider);
        expect(state.isLoading, false);
        expect(state.results.length, 10);
        expect(state.hasReachedMax, false);
        expect(state.stage, SearchStage.results);

        await controller.fetchNextPage();
        await Future.delayed(const Duration(milliseconds: 900));

        state = container.read(provider);
        expect(state.results.length, 20);
        expect(state.isFetchingMore, false);
      },
    );

    test('sets hasReachedMax when results are fewer than limit', () async {
      final container = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(MockSearchRepository()),
        ],
      );
      addTearDown(container.dispose);

      final provider = searchResultsProvider('Test');
      container.read(provider.notifier);

      await Future.delayed(const Duration(milliseconds: 900));

      final controller = container.read(provider.notifier);
      await controller.fetchNextPage();
      await Future.delayed(const Duration(milliseconds: 900));
      await controller.fetchNextPage();
      await Future.delayed(const Duration(milliseconds: 900));
      await controller.fetchNextPage();
      await Future.delayed(const Duration(milliseconds: 900));

      final state = container.read(provider);
      expect(state.hasReachedMax, true);
    });

    test('preserves existing results when fetchNextPage fails', () async {
      final container = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(MockSearchRepository()),
        ],
      );
      addTearDown(container.dispose);

      final provider = searchResultsProvider('error');
      container.read(provider.notifier);

      await Future.delayed(const Duration(milliseconds: 900));

      var state = container.read(provider);
      expect(state.error, isNotNull);
      expect(state.results, isEmpty);
      expect(state.stage, SearchStage.error);
    });

    test('empty results transition to empty stage', () async {
      final container = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(MockSearchRepository()),
        ],
      );
      addTearDown(container.dispose);

      final provider = searchResultsProvider('no-results');
      container.read(provider.notifier);

      await Future.delayed(const Duration(milliseconds: 900));

      final state = container.read(provider);
      expect(state.stage, SearchStage.empty);
    });

    test('updateSort triggers a fresh fetch', () async {
      final container = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(MockSearchRepository()),
        ],
      );
      addTearDown(container.dispose);

      final provider = searchResultsProvider('Paracetamol');
      final controller = container.read(provider.notifier);

      await Future.delayed(const Duration(milliseconds: 900));

      controller.updateSort(SortOption.lowestPrice);
      await Future.delayed(const Duration(milliseconds: 900));

      final state = container.read(provider);
      expect(state.sort, SortOption.lowestPrice);
    });

    test(
      'updateFilters preserves active category and brand selections',
      () async {
        final container = ProviderContainer(
          overrides: [
            searchRepositoryProvider.overrideWithValue(MockSearchRepository()),
          ],
        );
        addTearDown(container.dispose);

        final provider = searchResultsProvider('Paracetamol');
        final controller = container.read(provider.notifier);

        controller.updateFilters({
          'in_stock': true,
          'max_distance': 5.0,
          'max_price': 250.0,
          'min_rating': 4.0,
          'category': 'Health',
          'brand': 'Dettol',
        });
        await Future.delayed(const Duration(milliseconds: 900));

        final state = container.read(provider);
        expect(state.inStockOnly, isTrue);
        expect(state.maxDistance, 5.0);
        expect(state.maxPrice, 250.0);
        expect(state.minRating, 4.0);
        expect(state.categoryFilter, 'Health');
        expect(state.brandFilter, 'Dettol');
        expect(state.hasActiveFilters, isTrue);
      },
    );
  });

  group('SearchEventTracker', () {
    test('tracks results shown and error events', () async {
      final events = <SearchEvent>[];
      final tracker = _RecordingTracker(events);

      final container = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(MockSearchRepository()),
          searchEventTrackerProvider.overrideWithValue(tracker),
        ],
      );
      addTearDown(container.dispose);

      container.read(searchResultsProvider('Paracetamol').notifier);
      await Future.delayed(const Duration(milliseconds: 900));

      expect(events.any((e) => e is ResultsShownEvent), isTrue);

      container.read(searchResultsProvider('error').notifier);
      await Future.delayed(const Duration(milliseconds: 900));

      expect(events.any((e) => e is SearchErrorEvent), isTrue);
    });
  });
}

class _RecordingTracker implements SearchEventTracker {
  final List<SearchEvent> events;

  _RecordingTracker(this.events);

  @override
  void track(SearchEvent event) {
    events.add(event);
  }
}
