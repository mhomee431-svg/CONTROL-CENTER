import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/data/notifications_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/domain/notification_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/presentation/controllers/notifications_controller.dart';

import 'fakes.dart';

/// Builds a test notification with a stable timestamp.
ShopkeeperNotification _notification({
  int id = 1,
  String type = 'INVENTORY_LOW',
  String title = 'Low stock: Aashirvaad Atta',
  bool isRead = false,
}) =>
    ShopkeeperNotification(
      id: id,
      title: title,
      body: 'Only 3 left in store',
      type: type,
      isRead: isRead,
      createdAt: DateTime(2026, 9, 10, 8),
    );

void main() {
  group('NotificationsController', () {
    ProviderContainer makeContainer(
        FakeNotificationsRepo repo,
        {int? shopId}) {
      final container = ProviderContainer(overrides: [
        notificationsRepositoryProvider.overrideWithValue(repo),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider.overrideWith(
            () => SelectedShopOverride(shopId == null ? null : ownerShop(id: shopId))),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('loads notifications for the selected shop', () async {
      final page = NotificationsPage(
        items: [_notification()],
        unreadCount: 1,
      );
      final fake = FakeNotificationsRepo(page: page);
      final container = makeContainer(fake, shopId: 10);

      await container.read(notificationsControllerProvider.notifier).load();

      final state = container.read(notificationsControllerProvider);
      expect(state.status, NotificationsStatus.ready);
      expect(state.items, hasLength(1));
      expect(state.unreadCount, 1);
      expect(state.items.first.type, 'INVENTORY_LOW');
      expect(state.items.first.isUnread, isTrue);
      expect(fake.fetchCalls, 1);
    });

    test('error state surfaces a friendly message', () async {
      final fake = FakeNotificationsRepo(
        error: const ApiException(
            statusCode: 403, message: 'You do not have access to this shop.'),
      );
      final container = makeContainer(fake, shopId: 10);

      await container.read(notificationsControllerProvider.notifier).load();

      final state = container.read(notificationsControllerProvider);
      expect(state.status, NotificationsStatus.error);
      expect(state.message, contains('do not have access'));
    });

    test('no selected shop stays ready + empty', () async {
      final fake = FakeNotificationsRepo();
      final container = makeContainer(fake);

      await container.read(notificationsControllerProvider.notifier).load();

      final state = container.read(notificationsControllerProvider);
      expect(state.status, NotificationsStatus.ready);
      expect(state.items, isEmpty);
    });

    test('markAsRead updates the badge optimistically and calls the API',
        () async {
      final page =
          NotificationsPage(items: [_notification(id: 1)], unreadCount: 1);
      final fake = FakeNotificationsRepo(page: page);
      final container = makeContainer(fake, shopId: 10);
      await container.read(notificationsControllerProvider.notifier).load();

      await container
          .read(notificationsControllerProvider.notifier)
          .markAsRead(1);

      final state = container.read(notificationsControllerProvider);
      expect(state.items.first.isRead, isTrue);
      expect(state.unreadCount, 0);
      expect(fake.markedRead, [1]);
    });

    test('markAllAsRead zeroes the badge and marks every row', () async {
      final page = NotificationsPage(
        items: [
          _notification(id: 1, type: 'INVENTORY_LOW'),
          _notification(id: 2, type: 'PRICE_UPDATE'),
        ],
        unreadCount: 2,
      );
      final fake = FakeNotificationsRepo(page: page);
      final container = makeContainer(fake, shopId: 10);
      await container.read(notificationsControllerProvider.notifier).load();

      await container
          .read(notificationsControllerProvider.notifier)
          .markAllAsRead();

      final state = container.read(notificationsControllerProvider);
      expect(state.items.every((n) => n.isRead), isTrue);
      expect(state.unreadCount, 0);
      expect(fake.markedRead, containsAll([1, 2]));
      // One bulk call — never one request per row.
      expect(fake.markAllAsReadCalls, 1);
    });

    test('markAllAsRead with nothing unread never calls the API', () async {
      final page = NotificationsPage(
        items: [_notification(id: 1, isRead: true)],
        unreadCount: 0,
      );
      final fake = FakeNotificationsRepo(page: page);
      final container = makeContainer(fake, shopId: 10);
      await container.read(notificationsControllerProvider.notifier).load();

      await container
          .read(notificationsControllerProvider.notifier)
          .markAllAsRead();

      expect(fake.markAllAsReadCalls, 0);
      expect(fake.markedRead, isEmpty);
    });
  });

  // Rendered by BOTH notification surfaces (the Alerts tab and the Home
  // dashboard strip) through one shared helper — `now` is injected so these
  // assertions never depend on the wall clock.
  group('notificationTimeLabel', () {
    final now = DateTime(2026, 9, 16, 12);

    test('renders the relative buckets', () {
      expect(
        notificationTimeLabel(now.subtract(const Duration(seconds: 30)),
            now: now),
        'just now',
      );
      expect(
        notificationTimeLabel(now.subtract(const Duration(minutes: 12)),
            now: now),
        '12m ago',
      );
      expect(
        notificationTimeLabel(now.subtract(const Duration(hours: 3)), now: now),
        '3h ago',
      );
      expect(
        notificationTimeLabel(now.subtract(const Duration(days: 2)), now: now),
        '2d ago',
      );
    });

    test('falls back to a calendar date beyond a week', () {
      expect(
        notificationTimeLabel(DateTime(2026, 9, 4, 9), now: now),
        '4 Sep',
      );
    });
  });
}