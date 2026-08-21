import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_customer_app/features/notifications/presentation/controllers/notifications_controller.dart';

void main() {
  group('NotificationsController', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state contains mock notifications with unread count of 2', () {
      final state = container.read(notificationsControllerProvider);
      expect(state.length, 2);
      expect(container.read(notificationsControllerProvider.notifier).unreadCount, 2);
    });

    test('markAsRead updates item state correctly', () {
      final controller = container.read(notificationsControllerProvider.notifier);
      controller.markAsRead('n1');

      final state = container.read(notificationsControllerProvider);
      expect(state.firstWhere((n) => n.id == 'n1').isRead, isTrue);
      expect(controller.unreadCount, 1);
    });

    test('markAllAsRead marks all items as read', () {
      final controller = container.read(notificationsControllerProvider.notifier);
      controller.markAllAsRead();

      final state = container.read(notificationsControllerProvider);
      expect(state.every((n) => n.isRead), isTrue);
      expect(controller.unreadCount, 0);
    });

    test('clearAll removes all items', () {
      final controller = container.read(notificationsControllerProvider.notifier);
      controller.clearAll();

      expect(container.read(notificationsControllerProvider), isEmpty);
    });
  });
}