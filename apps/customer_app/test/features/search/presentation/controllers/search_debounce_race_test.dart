import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/performance/debouncer.dart';
import 'package:hyperlocal_app/features/search/domain/models/search_models.dart';
import 'package:hyperlocal_app/features/search/domain/search_repository.dart';
import 'package:hyperlocal_app/features/search/presentation/controllers/search_controller.dart';

/// Records every suggestion request and can hold each one open.
///
/// Both jobs matter below: the counter proves how MANY requests a burst of
/// typing produced, and the gate proves an old response cannot land on a newer
/// query.
class _SuggestionSpy implements SearchRepository {
  final List<String> requestedQueries = [];
  final List<Completer<List<SearchSuggestion>>> gates = [];

  @override
  Future<List<SearchSuggestion>> getSuggestions(String query) {
    requestedQueries.add(query);
    final gate = Completer<List<SearchSuggestion>>();
    gates.add(gate);
    return gate.future;
  }

  /// Completes the request at [index] (0 = the earliest query typed) with a
  /// single suggestion carrying [text].
  ///
  /// Index-based release is essential here. The whole point of the test is to
  /// answer the requests OUT OF ORDER, and `releaseOldest` can only ever answer
  /// them in the order they were typed -- which would hide the bug entirely.
  void releaseAt(int index, String text) {
    gates.removeAt(index).complete([SearchSuggestion(text: text)]);
  }

  void releaseOldest(String text) => releaseAt(0, text);

  @override
  Future<List<ShopProductResult>> searchProducts({
    required String query,
    required int page,
    required int limit,
    SortOption sort = SortOption.nearest,
    Map<String, dynamic>? filters,
    double? latitude,
    double? longitude,
  }) async => const [];

  @override
  Future<List<String>> getPopularSearches() async => const [];

  @override
  Future<List<String>> getRecentSearches() async => const [];

  @override
  Future<List<ShopProductResult>> lookupBarcode(
    String barcode, {
    double? latitude,
    double? longitude,
    int page = 1,
    int limit = 20,
  }) async => const [];
}

ProviderContainer _boot(_SuggestionSpy repo) {
  final container = ProviderContainer(
    overrides: [searchRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  // Watched for the whole test so the provider re-evaluates on every change.
  final subscription = container.listen(
    suggestionsProvider,
    (previous, next) {},
    fireImmediately: true,
  );
  addTearDown(subscription.close);
  return container;
}

void main() {
  group('search input debounce', () {
    test('a burst of keystrokes produces exactly one request', () {
      final repo = _SuggestionSpy();
      final container = _boot(repo);
      final debouncer = Debouncer(delay: const Duration(milliseconds: 20));
      addTearDown(debouncer.dispose);

      // Drives the debounce on a VIRTUAL clock.
      //
      // This test used to sleep 60ms of real time and hope the 20ms timer had
      // fired. Under parallel execution -- the suite runs files concurrently --
      // the machine can be busy enough that the timer has not fired by the time
      // the assertion runs, and the test fails having proved nothing.
      // `fakeAsync` makes "the debounce elapsed" an exact, instant event, so
      // this tests the debounce rather than the scheduler.
      fakeAsync((async) {
        // "D", "Do", "Dov", "Dove" typed at normal speed.
        for (final partial in ['D', 'Do', 'Dov', 'Dove']) {
          container.read(searchQueryProvider.notifier).onTextChanged(partial);
          debouncer.run(
            () => container
                .read(searchQueryProvider.notifier)
                .debouncedTextChanged(partial),
          );
          expect(
            container.read(searchQueryProvider).query,
            partial,
            reason: 'the text field must echo each keystroke right away',
          );
        }

        // Cross the debounce interval.
        async.elapse(const Duration(milliseconds: 25));

        expect(repo.requestedQueries, [
          'Dove',
        ], reason: 'only the settled query may reach the network');
      });
    });

    test('a settled query below two characters is never requested', () async {
      final repo = _SuggestionSpy();
      final container = _boot(repo);

      container.read(searchQueryProvider.notifier).debouncedTextChanged('D');
      await Future<void>.delayed(Duration.zero);

      expect(repo.requestedQueries, isEmpty);
    });
  });

  group('an older query cannot overwrite a newer one', () {
    test('"Dove" resolving after "Dove Shampoo" is ignored', () async {
      final repo = _SuggestionSpy();
      final container = _boot(repo);

      // The customer types "Dove" and the request goes out.
      container.read(searchQueryProvider.notifier).debouncedTextChanged('Dove');
      await Future<void>.delayed(Duration.zero);
      expect(repo.requestedQueries, ['Dove']);

      // They keep typing; the new query supersedes it.
      container
          .read(searchQueryProvider.notifier)
          .debouncedTextChanged('Dove Shampoo');
      await Future<void>.delayed(Duration.zero);
      expect(repo.requestedQueries, ['Dove', 'Dove Shampoo']);

      // The NEW request (index 1) answers first, then the OLD one (index 0)
      // lands late -- exactly the interleaving the requirement calls out.
      repo.releaseAt(1, 'Dove Shampoo 750ml');
      await Future<void>.delayed(Duration.zero);
      repo.releaseAt(0, 'Dove Soap 100g');
      await Future<void>.delayed(Duration.zero);

      final suggestions = container.read(suggestionsProvider).value ?? [];
      expect(suggestions.map((s) => s.text), ['Dove Shampoo 750ml']);
      expect(
        suggestions.map((s) => s.text),
        isNot(contains('Dove Soap 100g')),
        reason: 'the late "Dove" response must not overwrite the newer query',
      );
    });

    test('suggestions key off the settled query, not the keystroke', () async {
      final repo = _SuggestionSpy();
      final container = _boot(repo);

      container.read(searchQueryProvider.notifier).onTextChanged('milk');
      final state = container.read(searchQueryProvider);
      expect(state.query, 'milk');
      expect(state.debouncedQuery, '');
      expect(repo.requestedQueries, isEmpty);
    });
  });
}
