import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/data/holiday_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/holiday_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/presentation/controllers/holiday_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/presentation/widgets/holidays_section.dart';

import 'fakes.dart';

void main() {
  group('HolidaysController', () {
    ProviderContainer makeContainer(
      FakeHolidayRepository repo, {
      int? shopId = 10,
    }) {
      final container = ProviderContainer(overrides: [
        holidayRepositoryProvider.overrideWithValue(repo),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider.overrideWith(() =>
            SelectedShopOverride(shopId == null ? null : ownerShop(id: shopId))),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('loads holidays for the selected shop', () async {
      final repo = FakeHolidayRepository(holidays: [
        holidayFixture(id: 1, date: DateTime(2027, 3, 4)),
        holidayFixture(id: 2, date: DateTime(2027, 1, 10)),
      ]);
      final container = makeContainer(repo);

      await container.read(holidaysControllerProvider.notifier).load();

      final state = container.read(holidaysControllerProvider);
      expect(state.status, HolidaysStatus.ready);
      expect(state.items, hasLength(2));
      // Backend sorts by date — the controller preserves that order.
      expect(state.items.first.id, 2);
      expect(repo.listCalls, 1);
    });

    test('no shop selected fails fast without calling the API', () async {
      final repo = FakeHolidayRepository();
      final container = makeContainer(repo, shopId: null);

      await container.read(holidaysControllerProvider.notifier).load();

      final state = container.read(holidaysControllerProvider);
      expect(state.status, HolidaysStatus.noShop);
      expect(state.message, contains('No shop selected'));
      expect(repo.listCalls, 0);
    });

    test('403 becomes the owner-only message', () async {
      final repo = FakeHolidayRepository(
        listError: const ApiException(statusCode: 403, message: 'denied'),
      );
      final container = makeContainer(repo);

      await container.read(holidaysControllerProvider.notifier).load();

      final state = container.read(holidaysControllerProvider);
      expect(state.status, HolidaysStatus.error);
      expect(state.message, 'Only shop owners can manage holidays.');
    });

    test('offline failure becomes the network message', () async {
      final repo = FakeHolidayRepository(
        listError: const ApiException(message: 'Network error'),
      );
      final container = makeContainer(repo);

      await container.read(holidaysControllerProvider.notifier).load();

      final state = container.read(holidaysControllerProvider);
      expect(state.status, HolidaysStatus.error);
      expect(state.message, contains('No internet connection'));
    });

    test('add schedules the closure then reloads from the backend',
        () async {
      final repo = FakeHolidayRepository();
      final container = makeContainer(repo);
      // The section loads on mount — mirror that before mutating.
      await container.read(holidaysControllerProvider.notifier).load();

      final ok = await container
          .read(holidaysControllerProvider.notifier)
          .add(HolidayDraft(
            date: DateTime(2027, 8, 15),
            reason: 'Independence Day',
            recurringYearly: true,
          ));

      expect(ok, isTrue);
      expect(repo.addCalls, 1);
      expect(repo.addedDrafts.single.encodedDate, '2027-08-15');
      // The list is re-fetched from the backend after a successful add —
      // the state can never hold a stale copy (SSOT).
      expect(repo.listCalls, 2);
      final state = container.read(holidaysControllerProvider);
      expect(state.items, hasLength(1));
      expect(state.items.first.reason, 'Independence Day');
      expect(state.upcoming.first.isRecurringYearly, isTrue);
    });

    test('failed add reports the error and does not reload', () async {
      final repo = FakeHolidayRepository(
        addError: const ApiException(statusCode: 403, message: 'denied'),
      );
      final container = makeContainer(repo);

      final ok = await container
          .read(holidaysControllerProvider.notifier)
          .add(HolidayDraft(date: DateTime(2027, 5, 1)));

      expect(ok, isFalse);
      expect(repo.addCalls, 1);
      expect(repo.listCalls, 0);
      expect(container.read(holidaysControllerProvider).message,
          'Only shop owners can manage holidays.');
    });

    test('remove deletes the holiday and reloads', () async {
      final repo = FakeHolidayRepository(holidays: [
        holidayFixture(id: 7, date: DateTime(2027, 3, 4)),
      ]);
      final container = makeContainer(repo);
      await container.read(holidaysControllerProvider.notifier).load();

      final ok =
          await container.read(holidaysControllerProvider.notifier).remove(7);

      expect(ok, isTrue);
      expect(repo.removedIds, [7]);
      expect(repo.listCalls, 2);
      expect(container.read(holidaysControllerProvider).items, isEmpty);
    });

    test('upcoming/past slicing separates recurring and expired closures',
        () {
      final state = HolidaysState(status: HolidaysStatus.ready, items: [
        ShopHoliday(id: 1, date: DateTime(2027, 3, 4), reason: 'Holi'),
        // Long past, but yearly recurring → still relevant.
        ShopHoliday(
          id: 2,
          date: DateTime(2020, 8, 15),
          reason: 'Independence Day',
          isRecurringYearly: true,
        ),
        // Past one-off → record only.
        ShopHoliday(id: 3, date: DateTime(2020, 1, 1), reason: 'Old closure'),
      ]);

      expect(state.upcoming.map((h) => h.id), [1, 2]);
      expect(state.past.map((h) => h.id), [3]);
      expect(state.items.first.dateLabel, '04 Mar 2027');
    });
  });

  group('HolidaysSection (widget)', () {
    Widget wrap(FakeHolidayRepository repo, {bool canEdit = true}) =>
        ProviderScope(
          overrides: [
            holidayRepositoryProvider.overrideWithValue(repo),
            tokenStoreProvider.overrideWithValue(
                InMemoryTokenStore(accessToken: 'test-access-token')),
            selectedShopProvider
                .overrideWith(() => SelectedShopOverride(ownerShop(id: 10))),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [HolidaysSection(canEdit: canEdit)],
              ),
            ),
          ),
        );

    testWidgets('renders upcoming holidays with delete affordances',
        (tester) async {
      final repo = FakeHolidayRepository(holidays: [
        holidayFixture(id: 1, date: DateTime(2027, 3, 4), reason: 'Holi'),
        holidayFixture(
          id: 2,
          date: DateTime(2027, 8, 15),
          reason: 'Independence Day',
          recurring: true,
        ),
      ]);
      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      expect(find.text('Holidays'), findsOneWidget);
      expect(find.text('Holi'), findsOneWidget);
      expect(find.text('Independence Day'), findsOneWidget);
      expect(find.text('Every year'), findsOneWidget);
      // One-off holidays can be deleted; yearly-recurring ones have no
      // delete button (they are re-edited, never silently lost).
      expect(find.byKey(const Key('holiday-delete-1')), findsOneWidget);
      expect(find.byKey(const Key('holiday-delete-2')), findsNothing);
    });

    testWidgets('shows the backend error with a working Retry',
        (tester) async {
      final repo = FakeHolidayRepository(
        holidays: [holidayFixture(id: 1, date: DateTime(2027, 3, 4))],
        listError: const ApiException(statusCode: 500, message: 'Server down'),
      );
      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      expect(find.text('Server down'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // Retry recovers once the backend stops failing.
      repo.listError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Server down'), findsNothing);
      expect(find.text('04 Mar 2027'), findsOneWidget);
    });

    testWidgets('hides the add affordance when the shop is read-only',
        (tester) async {
      final repo = FakeHolidayRepository(holidays: [
        holidayFixture(id: 1, date: DateTime(2027, 3, 4)),
      ]);
      await tester.pumpWidget(wrap(repo, canEdit: false));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('holidays-add')), findsNothing);
      expect(find.byKey(const Key('holiday-delete-1')), findsNothing);
      expect(find.text('04 Mar 2027'), findsOneWidget);
    });
  });
}
