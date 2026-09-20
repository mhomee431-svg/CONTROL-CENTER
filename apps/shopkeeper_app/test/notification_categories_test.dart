import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/data/notifications_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/domain/notification_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/presentation/screens/notifications_screen.dart';

import 'fakes.dart';

/// One notification row with a stable timestamp.
ShopkeeperNotification _row({
  required int id,
  required String type,
  required String title,
}) =>
    ShopkeeperNotification(
      id: id,
      title: title,
      body: 'Body for $type',
      type: type,
      isRead: false,
      createdAt: DateTime(2026, 9, 18, 21, 19),
    );

Future<void> _pumpScreen(
  WidgetTester tester,
  List<ShopkeeperNotification> items,
) async {
  final repo = FakeNotificationsRepo(
    page: NotificationsPage(items: items, unreadCount: items.length),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationsRepositoryProvider.overrideWithValue(repo),
        tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(accessToken: 'test-access-token'),
        ),
        selectedShopProvider.overrideWith(
          () => SelectedShopOverride(ownerShop(id: 10)),
        ),
      ],
      child: const MaterialApp(home: NotificationsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('NotificationCategory taxonomy', () {
    test('all nine merchant categories are declared', () {
      expect(NotificationCategory.values, hasLength(9));
      expect(
        NotificationCategory.values.map((c) => c.label).toList(),
        [
          'Inventory',
          'Products',
          'Pricing',
          'Offers',
          'Imports',
          'POS',
          'Account',
          'System',
          'Support',
        ],
      );
    });

    test('every category claims at least one backend type', () {
      for (final category in NotificationCategory.values) {
        expect(category.types, isNotEmpty,
            reason: '${category.label} claims no backend type');
      }
    });

    test('no backend type is claimed by two categories', () {
      final seen = <String, NotificationCategory>{};
      for (final category in NotificationCategory.values) {
        for (final type in category.types) {
          expect(seen.containsKey(type), isFalse,
              reason: '$type claimed by two categories');
          seen[type] = category;
        }
      }
    });

    test('maps each backend category type to its category', () {
      expect(NotificationCategory.of('INVENTORY_UPDATE'),
          NotificationCategory.inventory);
      expect(NotificationCategory.of('PRODUCT'), NotificationCategory.products);
      expect(NotificationCategory.of('PRICING'), NotificationCategory.pricing);
      expect(
          NotificationCategory.of('SHOP_OFFER'), NotificationCategory.offers);
      expect(NotificationCategory.of('IMPORT'), NotificationCategory.imports);
      expect(NotificationCategory.of('POS_SYNC'), NotificationCategory.pos);
      expect(NotificationCategory.of('ACCOUNT'), NotificationCategory.account);
      expect(NotificationCategory.of('SYSTEM'), NotificationCategory.system);
      expect(
          NotificationCategory.of('SUPPORT'), NotificationCategory.support);
    });

    test('carries the legacy aliases still present in the database', () {
      expect(NotificationCategory.of('INVENTORY_LOW'),
          NotificationCategory.inventory);
      expect(NotificationCategory.of('STOCK_UPDATE'),
          NotificationCategory.inventory);
      expect(NotificationCategory.of('PRICE_UPDATE'),
          NotificationCategory.pricing);
      expect(NotificationCategory.of('SHOP_VERIFICATION'),
          NotificationCategory.account);
      expect(NotificationCategory.of('SUBSCRIPTION'),
          NotificationCategory.account);
      // Broadcasts stored before the typed-pipeline migration carry "admin".
      expect(
          NotificationCategory.of('ADMIN'), NotificationCategory.system);
    });

    test('an unregistered type has no category instead of throwing', () {
      expect(NotificationCategory.of('SOMETHING_NEW'), isNull);
      expect(NotificationCategory.of(''), isNull);
    });

    test('matching is case-insensitive', () {
      expect(NotificationCategory.products.matches('product'), isTrue);
      expect(NotificationCategory.products.matches('Product'), isTrue);
      expect(NotificationCategory.products.matches('PRICING'), isFalse);
    });
  });

  group('notificationIcon', () {
    test('renders the new category types', () {
      expect(notificationIcon('PRODUCT'), Icons.inventory_outlined);
      expect(notificationIcon('PRICING'), Icons.price_change_outlined);
      expect(notificationIcon('IMPORT'), Icons.upload_file_outlined);
      expect(notificationIcon('SHOP_OFFER'), Icons.local_offer_outlined);
      expect(notificationIcon('ACCOUNT'), Icons.manage_accounts_outlined);
      expect(notificationIcon('SYSTEM'), Icons.campaign_outlined);
      expect(notificationIcon('ADMIN'), Icons.campaign_outlined);
      expect(notificationIcon('SUPPORT'), Icons.support_agent_outlined);
      expect(notificationIcon('INVENTORY_UPDATE'), Icons.inventory_2_outlined);
    });

    test('keeps the pre-existing mappings stable', () {
      expect(notificationIcon('INVENTORY_LOW'), Icons.inventory_2_outlined);
      expect(notificationIcon('POS_SYNC'), Icons.sync_outlined);
      expect(notificationIcon('SUBSCRIPTION'), Icons.card_membership_outlined);
      expect(notificationIcon('ORDER'), Icons.shopping_bag_outlined);
    });

    test('is case-insensitive and never throws on an unknown type', () {
      expect(notificationIcon('product'), Icons.inventory_outlined);
      expect(notificationIcon('BRAND_NEW_TYPE'), Icons.notifications_outlined);
    });
  });

  group('Alerts category filter', () {
    final items = [
      _row(id: 1, type: 'INVENTORY_LOW', title: 'Low stock: Atta'),
      _row(id: 2, type: 'PRICING', title: 'Price update successful'),
      _row(id: 3, type: 'IMPORT', title: 'Import completed'),
    ];

    testWidgets('shows All plus the category chips', (tester) async {
      await _pumpScreen(tester, items);
      expect(find.byKey(const Key('notification-filter-all')), findsOneWidget);
      expect(
          find.byKey(const Key('notification-filter-products')), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Products'), findsOneWidget);
    });

    testWidgets('starts unfiltered', (tester) async {
      await _pumpScreen(tester, items);
      expect(find.text('Low stock: Atta'), findsOneWidget);
      expect(find.text('Price update successful'), findsOneWidget);
      expect(find.text('Import completed'), findsOneWidget);
    });

    testWidgets('filters down to a single category', (tester) async {
      await _pumpScreen(tester, items);
      await tester.tap(find.byKey(const Key('notification-filter-pricing')));
      await tester.pumpAndSettle();

      expect(find.text('Price update successful'), findsOneWidget);
      expect(find.text('Low stock: Atta'), findsNothing);
      expect(find.text('Import completed'), findsNothing);
    });

    testWidgets('All restores every row', (tester) async {
      await _pumpScreen(tester, items);
      await tester.tap(find.byKey(const Key('notification-filter-pricing')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notification-filter-all')));
      await tester.pumpAndSettle();

      expect(find.text('Low stock: Atta'), findsOneWidget);
      expect(find.text('Import completed'), findsOneWidget);
    });

    testWidgets('a category with no rows explains itself', (tester) async {
      await _pumpScreen(tester, items);
      await tester.tap(find.byKey(const Key('notification-filter-products')));
      await tester.pumpAndSettle();

      expect(find.text('No Products notifications'), findsOneWidget);
      expect(find.text('Low stock: Atta'), findsNothing);
    });

    testWidgets('an empty inbox keeps the original copy', (tester) async {
      await _pumpScreen(tester, const <ShopkeeperNotification>[]);
      expect(find.text('No notifications yet'), findsOneWidget);
    });
  });
}