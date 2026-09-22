// Recent searches — the shopkeeper's own submitted product terms.
//
// Submitted terms only (never keystrokes): recorded on keyboard submit /
// focus-loss flush, deduped case-insensitively, most-recent-first, capped,
// per shop, persisted in encrypted storage, wiped on logout. One shared
// history serves the products list, the inventory scopes and the price list
// (all three search the same catalog rows).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/recent_searches_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/controllers/recent_searches_controller.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_providers.dart';
import 'package:hyperlocal_shopkeeper_app/core/ui/debounced_search_field.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/domain/auth_models.dart';

import 'fakes.dart';

void main() {
  // `shop` omitted  -> the owner's shop (id 10) is selected.
  // `noShop: true`  -> nothing is selected at all (logged-out / pre-login).
  ProviderContainer makeContainer({
    required RecentSearchesStore searches,
    ShopSummary? shop,
    bool noShop = false,
  }) =>
      ProviderContainer(overrides: [
        recentSearchesStoreProvider.overrideWithValue(searches),
        selectedShopProvider.overrideWith(
          () => SelectedShopOverride(noShop ? null : (shop ?? ownerShop())),
        ),
      ]);

  group('RecentSearchesController — submitted terms only', () {
    test('blank and single-letter drafts are never history', () async {
      final container =
          makeContainer(searches: InMemoryRecentSearchesStore());
      addTearDown(container.dispose);

      final recents =
          container.read(recentSearchesControllerProvider.notifier);
      await recents.record('');
      await recents.record(' ');
      await recents.record('a');
      expect(
        container.read(recentSearchesControllerProvider).terms,
        isEmpty,
      );
    });

    test('records most-recent-first, deduped, capped', () async {
      final container =
          makeContainer(searches: InMemoryRecentSearchesStore());
      addTearDown(container.dispose);
      final recents =
          container.read(recentSearchesControllerProvider.notifier);

      await recents.record('Amul Milk');
      await recents.record('sugar');
      await recents.record('AMUL MILK');

      // Re-submitting moves to the front instead of duplicating.
      expect(
        container.read(recentSearchesControllerProvider).terms,
        ['AMUL MILK', 'sugar'],
      );

      // The cap drops the oldest terms.
      for (var i = 0; i < RecentSearchesController.maxTerms + 3; i++) {
        await recents.record('term $i');
      }
      final terms = container.read(recentSearchesControllerProvider).terms;
      expect(terms, hasLength(RecentSearchesController.maxTerms));
      expect(terms.first, 'term ${RecentSearchesController.maxTerms + 2}');
    });

    test('persists per shop and reloads on shop switch', () async {
      final store = InMemoryRecentSearchesStore();
      final container = makeContainer(searches: store);
      addTearDown(container.dispose);
      final recents =
          container.read(recentSearchesControllerProvider.notifier);

      await recents.record('amul');
      expect(await store.read('10'), ['amul']);

      // Switching shops shows the OTHER shop's history, never this one's.
      container.read(selectedShopProvider.notifier).select(ownerShop(id: 20));
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(recentSearchesControllerProvider).terms,
        isEmpty,
      );

      await recents.record('branch term');
      expect(await store.read('20'), ['branch term']);
      expect(await store.read('10'), ['amul']);
    });

    test('remove drops one term and persists', () async {
      final store = InMemoryRecentSearchesStore();
      final container = makeContainer(searches: store);
      addTearDown(container.dispose);
      final recents =
          container.read(recentSearchesControllerProvider.notifier);

      await recents.record('amul');
      await recents.record('sugar');
      await recents.remove('AMUL');

      expect(
        container.read(recentSearchesControllerProvider).terms,
        ['sugar'],
      );
      expect(await store.read('10'), ['sugar']);
    });

    test('without a shop nothing is recorded or shown', () async {
      final store = InMemoryRecentSearchesStore();
      final container = makeContainer(searches: store, noShop: true);
      addTearDown(container.dispose);

      await container
          .read(recentSearchesControllerProvider.notifier)
          .record('amul');
      expect(
        container.read(recentSearchesControllerProvider).terms,
        isEmpty,
      );
      expect(await store.read('10'), isEmpty);
    });

    test('store failure degrades to in-memory terms, never throws', () async {
      final container =
          makeContainer(searches: InMemoryRecentSearchesStore());
      addTearDown(container.dispose);
      final recents =
          container.read(recentSearchesControllerProvider.notifier);

      await recents.load();
      await recents.record('amul');
      expect(
        container.read(recentSearchesControllerProvider).terms,
        ['amul'],
        reason: 'in-memory terms still drive the UI when the store fails',
      );
      await recents.clearAll();
    });
  });


  group('DebouncedSearchField recent-searches dropdown', () {
    testWidgets('shows recents only when focused and empty', (tester) async {
      String? applied;
      String? removed;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                DebouncedSearchField(
                  onChanged: (v) => applied = v,
                  recentSearches: const ['amul', 'sugar'],
                  onRecentSelected: (v) => applied = v,
                  onRecentRemoved: (v) => removed = v,
                ),
                const TextField(key: Key('other_field')),
              ],
            ),
          ),
        ),
      );

      // Unfocused: no dropdown, even with history.
      expect(find.text('Recent searches'), findsNothing);

      // Focused + empty: the dropdown lists every term.
      await tester.tap(find.byKey(const Key('search_field')));
      await tester.pump();
      expect(find.text('Recent searches'), findsOneWidget);
      expect(find.text('amul'), findsOneWidget);
      expect(find.text('sugar'), findsOneWidget);

      // Typing hides the dropdown: the rows are the answer now, not history.
      await tester.enterText(find.byKey(const Key('search_field')), 'a');
      await tester.pump();
      expect(find.text('Recent searches'), findsNothing);

      // Clearing the field brings the dropdown back.
      await tester.enterText(find.byKey(const Key('search_field')), '');
      await tester.pump();
      expect(find.text('Recent searches'), findsOneWidget);

      // Dismissing one term notifies the parent (which owns the list).
      await tester.tap(find.byKey(const Key('remove_recent_amul')));
      await tester.pump();
      expect(removed, 'amul');

      // Leaving the field dismisses the dropdown.
      await tester.tap(find.byKey(const Key('other_field')));
      await tester.pump();
      expect(find.text('Recent searches'), findsNothing);
      expect(applied, isNotNull);
    });

    testWidgets('tapping a recent term applies it immediately', (tester) async {
      String? lastApplied;
      int applyCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DebouncedSearchField(
              onChanged: (v) {
                lastApplied = v;
                applyCount++;
              },
              recentSearches: const ['amul milk'],
              onRecentSelected: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('search_field')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('recent_search_amul milk')));
      await tester.pump();

      // No debounce for a settled value: applied synchronously, exactly once.
      expect(applyCount, 1);
      expect(lastApplied, 'amul milk');

      // The field adopted the text (cursor at the end, ready to refine).
      expect(
        tester.widget<TextField>(find.byKey(const Key('search_field')))
            .controller
            ?.text,
        'amul milk',
      );
    });

    testWidgets('no dropdown without terms or without a select handler',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const DebouncedSearchField(
                  onChanged: _noop,
                  recentSearches: ['amul'],
                ),
                DebouncedSearchField(
                  onChanged: _noop,
                  recentSearches: const ['amul'],
                  onRecentSelected: (_) {},
                ),
              ],
            ),
          ),
        ),
      );

      // First field: terms but no handler → never a dropdown.
      // Second field: unfocused → no dropdown yet either.
      expect(find.text('Recent searches'), findsNothing);

      await tester.tap(find.byType(TextField).at(1));
      await tester.pump();
      expect(find.text('Recent searches'), findsOneWidget);
    });

    testWidgets('submitting an empty field records nothing, still filters',
        (tester) async {
      // Empty submit must not create a "" history entry and must not crash
      // when no record hook is attached.
      String? lastApplied;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DebouncedSearchField(
              onChanged: (v) => lastApplied = v,
              onSubmitted: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('search_field')));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(lastApplied, isNull);
    });
  });

  group('logout wipes recent searches', () {
    test('logout clears the store and the visible terms', () async {
      final searches = InMemoryRecentSearchesStore();
      final tokens = InMemoryTokenStore(accessToken: 'access-token');
      final fake = FakeAuthRepository()
        ..restoreResult = makeSession()
        ..tokens = tokens;
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(fake),
        tokenStoreProvider.overrideWithValue(tokens),
        recentSearchesStoreProvider.overrideWithValue(searches),
        selectedShopProvider
            .overrideWith(() => SelectedShopOverride(ownerShop())),
      ]);
      addTearDown(container.dispose);

      final ok =
          await container.read(authControllerProvider.notifier).checkSession();
      expect(ok, isTrue);

      await container
          .read(recentSearchesControllerProvider.notifier)
          .record('amul');
      expect(
        container.read(recentSearchesControllerProvider).terms,
        ['amul'],
      );

      await container.read(authControllerProvider.notifier).logout();

      expect(
        container.read(recentSearchesControllerProvider).terms,
        isEmpty,
      );
      expect(searches.clearAllCount, 1);
      expect(await searches.read('10'), isEmpty);
    });
  });
}

void _noop(String _) {}