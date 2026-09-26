import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/features/notifications/data/mock_notification_repository.dart';
import 'package:hyperlocal_app/features/notifications/domain/models/app_notification.dart';
import 'package:hyperlocal_app/features/notifications/presentation/controllers/notifications_controller.dart';
import 'package:hyperlocal_app/features/notifications/domain/notification_repository.dart';

void main() {
  group('NotificationsController', () {
    late ProviderContainer container;
    late MockNotificationRepository repository;

    setUp(() {
      repository = MockNotificationRepository(delay: Duration.zero);
      container = ProviderContainer(
        overrides: [
          notificationsRepositoryProvider.overrideWithValue(repository),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    /// Waits until the controller leaves its initial loading state.
    Future<AsyncValue<List<AppNotification>>> settle(
      ProviderContainer target,
    ) async {
      target.read(notificationsControllerProvider);
      for (var i = 0; i < 200; i++) {
        final s = target.read(notificationsControllerProvider);
        if (!s.isLoading && !s.isRefreshing) return s;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      return target.read(notificationsControllerProvider);
    }

    Future<List<AppNotification>> waitForLoad() async {
      final s = await settle(container);
      return s.value ?? [];
    }

    test(
      'loads seed notifications covering all customer-facing types',
      () async {
        final notifications = await waitForLoad();

        expect(notifications.length, 5);
        expect(
          notifications.map((n) => n.type).toSet(),
          equals({
            NotificationType.priceDrop,
            NotificationType.productAvailable,
            NotificationType.offer,
            NotificationType.shopUpdate,
            NotificationType.system,
          }),
        );
        // Unread badge: 4 unread + 1 pre-read welcome message.
        expect(container.read(unreadCountProvider), 4);
      },
    );

    test('markAsRead updates item state optimistically and persists', () async {
      await waitForLoad();
      final controller = container.read(
        notificationsControllerProvider.notifier,
      );

      await controller.markAsRead('n1');

      final state = container.read(notificationsControllerProvider).value ?? [];
      expect(state.firstWhere((n) => n.id == 'n1').isRead, isTrue);
      expect(state.firstWhere((n) => n.id == 'n2').isRead, isFalse);
      expect(container.read(unreadCountProvider), 3);
      // Repository store reflects the change too (survives refresh).
      final reloaded = await repository.getNotifications();
      expect(reloaded.firstWhere((n) => n.id == 'n1').isRead, isTrue);
    });

    test('markAllAsRead clears the unread badge', () async {
      await waitForLoad();
      final controller = container.read(
        notificationsControllerProvider.notifier,
      );

      await controller.markAllAsRead();

      final state = container.read(notificationsControllerProvider).value ?? [];
      expect(state.every((n) => n.isRead), isTrue);
      expect(container.read(unreadCountProvider), 0);
    });

    test('markAsRead on unknown id is a safe no-op', () async {
      await waitForLoad();
      final controller = container.read(
        notificationsControllerProvider.notifier,
      );

      await controller.markAsRead('does-not-exist');

      expect(container.read(unreadCountProvider), 4);
    });

    test('refresh reloads from the repository', () async {
      await waitForLoad();
      expect(container.read(unreadCountProvider), 4);

      await repository.markAllAsRead();
      await container.read(notificationsControllerProvider.notifier).refresh();
      await settle(container);

      expect(container.read(unreadCountProvider), 0);
    });

    test(
      'load failure surfaces an error state (not a fake empty list)',
      () async {
        final failing = ProviderContainer(
          overrides: [
            notificationsRepositoryProvider.overrideWithValue(
              MockNotificationRepository(
                delay: Duration.zero,
                failureMode: MockFailureMode.load,
              ),
            ),
          ],
        );
        addTearDown(failing.dispose);

        final state = await settle(failing);

        expect(state.hasError, isTrue);
        expect(state.value, isNull);
      },
    );

    test('mark-read failures keep the optimistic update', () async {
      final optimistic = ProviderContainer(
        overrides: [
          notificationsRepositoryProvider.overrideWithValue(
            MockNotificationRepository(
              delay: Duration.zero,
              failureMode: MockFailureMode.markRead,
            ),
          ),
        ],
      );
      addTearDown(optimistic.dispose);
      await settle(optimistic);

      await optimistic
          .read(notificationsControllerProvider.notifier)
          .markAsRead('n1');

      final state =
          optimistic.read(notificationsControllerProvider).value ?? [];
      expect(state.firstWhere((n) => n.id == 'n1').isRead, isTrue);
    });
  });
}
