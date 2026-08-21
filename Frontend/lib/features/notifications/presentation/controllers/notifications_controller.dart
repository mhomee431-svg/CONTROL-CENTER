import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../data/api_notification_repository.dart';
import '../../domain/models/app_notification.dart';

final notificationsControllerProvider =
    NotifierProvider<NotificationsController, List<AppNotification>>(
  NotificationsController.new,
);

class NotificationsController extends Notifier<List<AppNotification>> {
  ApiNotificationRepository? _repository;

  @override
  List<AppNotification> build() {
    _repository = ApiNotificationRepository(ref.watch(apiClientProvider));
    _loadNotifications();
    return [];
  }

  Future<void> _loadNotifications() async {
    try {
      final notifications = await _repository!.getNotifications();
      state = notifications;
    } catch (_) {
      // Keep empty state on error; UI shows empty view
      state = [];
    }
  }

  Future<void> markAsRead(String id) async {
    state = [
      for (final n in state)
        if (n.id == id) n.copyWith(isRead: true) else n
    ];
    try {
      await _repository!.markAsRead(id);
    } catch (_) {
      // Optimistic update; ignore failure in Phase 13
    }
  }

  Future<void> markAllAsRead() async {
    state = [for (final n in state) n.copyWith(isRead: true)];
    try {
      await _repository!.markAllAsRead();
    } catch (_) {
      // Optimistic update; ignore failure in Phase 13
    }
  }

  void clearAll() {
    state = [];
  }

  int get unreadCount => state.where((n) => !n.isRead).length;
}