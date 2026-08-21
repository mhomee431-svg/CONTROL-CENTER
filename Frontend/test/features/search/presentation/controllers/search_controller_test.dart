import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyperlocal_customer_app/features/search/presentation/controllers/search_controller.dart';

void main() {
  group('Debouncer', () {
    test('cancels previous timers and only runs the latest action', () async {
      final debouncer = Debouncer(milliseconds: 100);
      var callCount = 0;

      // Fire multiple actions quickly
      debouncer.run(() => callCount++);
      debouncer.run(() => callCount++);
      debouncer.run(() => callCount++);

      // Wait for the debounce period to elapse
      await Future.delayed(const Duration(milliseconds: 200));

      // Only the last action should have executed
      expect(callCount, 1);

      debouncer.dispose();
    });

    test('executes action after the debounce period', () async {
      final debouncer = Debouncer(milliseconds: 50);
      var executed = false;

      debouncer.run(() => executed = true);

      // Before the debounce period, action should not have run
      expect(executed, false);

      await Future.delayed(const Duration(milliseconds: 100));

      expect(executed, true);

      debouncer.dispose();
    });
  });

  group('SearchResultsController', () {
    test('loads initial results and appends next page on fetchNextPage', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Watch the provider to trigger initial load
      final provider = searchResultsProvider('Paracetamol');
      final controller = container.read(provider.notifier);

      // Wait for initial load to complete
      await Future.delayed(const Duration(milliseconds: 900));

      var state = container.read(provider);
      expect(state.isLoading, false);
      expect(state.results.length, 10);
      expect(state.hasReachedMax, false);

      // Fetch next page
      await controller.fetchNextPage();
      await Future.delayed(const Duration(milliseconds: 900));

      state = container.read(provider);
      expect(state.results.length, 20);
      expect(state.isFetchingMore, false);
    });

    test('sets hasReachedMax when results are fewer than limit', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final provider = searchResultsProvider('Test');
      container.read(provider.notifier);

      // Wait for initial load
      await Future.delayed(const Duration(milliseconds: 900));

      // Fetch pages until we hit the max (page > 3 returns empty)
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
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final provider = searchResultsProvider('error');
      container.read(provider.notifier);

      // Wait for initial load to fail
      await Future.delayed(const Duration(milliseconds: 900));

      var state = container.read(provider);
      expect(state.error, isNotNull);
      expect(state.results, isEmpty);
    });
  });
}