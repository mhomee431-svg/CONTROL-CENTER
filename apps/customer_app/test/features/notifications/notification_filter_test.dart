import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal_app/features/notifications/domain/models/app_notification.dart';
import 'package:hyperlocal_app/features/notifications/domain/models/device_token_registration.dart';
import 'package:hyperlocal_app/features/notifications/domain/models/notification_preferences.dart';
import 'package:hyperlocal_app/features/notifications/domain/notification_repository.dart';
import 'package:hyperlocal_app/features/notifications/presentation/controllers/notifications_controller.dart';
import 'package:hyperlocal_app/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:hyperlocal_app/features/notifications/presentation/widgets/notification_filter_bar.dart';

/// Deterministic repository used by the Alerts filter tests.
class _FakeNotificationRepository implements NotificationRepository {
  _FakeNotificationRepository(this.items);

  List<AppNotification> items;

  @override
  Future<List<AppNotification>> getNotifications() async => List.of(items);

  @override
  Future<void> markAsRead(String id) async {}

  @override
  Future<void> markAllAsRead() async {}

  @override
  Future<NotificationPreferences> getPreferences() async =>
      NotificationPreferences.defaults;

  @override
  Future<void> updatePreferences(NotificationPreferences preferences) async {}

  @override
  Future<void> registerDeviceToken(DeviceTokenRegistration registration) async {}

  @override
  Future<void> unregisterDeviceToken(String token) async {}
}

GoRouter _router() {
  return GoRouter(
    initialLocation: '/notifications',
    routes: [
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const NotificationsScreen(),
      ),
    ],
  );
}

AppNotification _row({
  required String id,
  required String title,
  required NotificationType type,
}) =>
    AppNotification(
      id: id,
      title: title,
      body: 'body',
      timestamp: DateTime(2026, 9, 18, 21, 19),
      type: type,
    );

/// One row per customer-facing type — no `productAvailable` row, so the
/// Availability filter is exercised as a legitimately empty category.
List<AppNotification> _seed() => [
      _row(id: 'n1', title: 'Price drop alert', type: NotificationType.priceDrop),
      _row(id: 'n2', title: 'Shop update', type: NotificationType.shopUpdate),
      _row(id: 'n3', title: 'Weekend deal', type: NotificationType.offer),
      _row(id: 'n4', title: 'Welcome', type: NotificationType.system),
      _row(id: 'n5', title: 'Order shipped', type: NotificationType.orderUpdate),
    ];

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    List<AppNotification> items,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationsRepositoryProvider
              .overrideWithValue(_FakeNotificationRepository(items)),
        ],
        child: MaterialApp.router(routerConfig: _router()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('NotificationFilter taxonomy', () {
    test('All matches every type (including ones it does not claim)', () {
      for (final type in NotificationType.values) {
        expect(
          NotificationFilter.all.matches(_row(id: 'x', title: 't', type: type)),
          isTrue,
        );
      }
    });

    test('every customer type is claimed by exactly one filter', () {
      for (final type in NotificationType.values) {
        final owners = NotificationFilter.values
            .where((f) => f.types?.contains(type) ?? false)
            .toList();
        expect(
          owners.length,
          1,
          reason: 'expected exactly one filter to own $type, got '
              '${owners.map((f) => f.name).toList()}',
        );
      }
    });

    test('matching is type-based, never title-based', () {
      expect(
        NotificationFilter.priceDrops.matches(
          _row(id: 'x', title: 'anything', type: NotificationType.priceDrop),
        ),
        isTrue,
      );
      expect(
        NotificationFilter.priceDrops.matches(
          _row(id: 'y', title: 'Price drop alert', type: NotificationType.system),
        ),
        isFalse,
      );
    });

    test('chip labels are unique and non-empty', () {
      final labels = NotificationFilter.values.map((f) => f.label).toList();
      expect(labels.where((l) => l.trim().isEmpty), isEmpty);
      expect(labels.toSet().length, labels.length);
    });
  });

  group('Alerts category filter', () {
    testWidgets('shows All plus every filter chip', (tester) async {
      await pumpScreen(tester, _seed());

      expect(find.byKey(const Key('notification-filter-all')), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Price Drops'), findsOneWidget);
      // The bar is a horizontal list, so chips scroll into existence lazily —
      // scroll each one into view to prove every category is reachable.
      final barScrollable = find.descendant(
        of: find.byType(NotificationFilterBar),
        matching: find.byType(Scrollable),
      );
      for (final filter in NotificationFilter.values) {
        final chip = find.byKey(Key('notification-filter-${filter.name}'));
        await tester.scrollUntilVisible(
          chip,
          120,
          scrollable: barScrollable,
        );
        expect(
          chip,
          findsOneWidget,
          reason: 'missing chip for ${filter.name}',
        );
      }
    });

    testWidgets('starts unfiltered with every row visible', (tester) async {
      await pumpScreen(tester, _seed());

      expect(find.text('Price drop alert'), findsOneWidget);
      expect(find.text('Shop update'), findsOneWidget);
      expect(find.text('Weekend deal'), findsOneWidget);
      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('Order shipped'), findsOneWidget);
    });

    testWidgets('filters down to a single category', (tester) async {
      await pumpScreen(tester, _seed());

      await tester.tap(find.byKey(const Key('notification-filter-priceDrops')));
      await tester.pumpAndSettle();

      expect(find.text('Price drop alert'), findsOneWidget);
      expect(find.text('Shop update'), findsNothing);
      expect(find.text('Weekend deal'), findsNothing);
    });

    testWidgets('All restores every row', (tester) async {
      await pumpScreen(tester, _seed());

      await tester.tap(find.byKey(const Key('notification-filter-offers')));
      await tester.pumpAndSettle();
      expect(find.text('Shop update'), findsNothing);

      await tester.tap(find.byKey(const Key('notification-filter-all')));
      await tester.pumpAndSettle();

      expect(find.text('Price drop alert'), findsOneWidget);
      expect(find.text('Shop update'), findsOneWidget);
      expect(find.text('Weekend deal'), findsOneWidget);
    });

    testWidgets('a category with no rows explains itself', (tester) async {
      await pumpScreen(tester, _seed());

      await tester
          .tap(find.byKey(const Key('notification-filter-availability')));
      await tester.pumpAndSettle();

      expect(find.text('No Availability notifications'), findsOneWidget);
      expect(find.text('Price drop alert'), findsNothing);
    });

    testWidgets('filtering never changes the unread badge', (tester) async {
      await pumpScreen(tester, _seed());

      // All five rows are unread; the badge is computed from the whole list.
      await tester.tap(find.byKey(const Key('notification-filter-priceDrops')));
      await tester.pumpAndSettle();

      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('an empty inbox keeps the original copy (no filter bar)',
        (tester) async {
      await pumpScreen(tester, const <AppNotification>[]);

      expect(find.text('No notifications yet'), findsOneWidget);
      expect(find.byKey(const Key('notification-filter-all')), findsNothing);
    });
  });
}