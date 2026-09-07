import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/env/env_config.dart';
import '../../../../core/network/api_client.dart';
import '../../data/api_notification_repository.dart';
import '../../data/mock_notification_repository.dart';
import '../../domain/models/app_notification.dart';
import '../../domain/notification_repository.dart';

/// Selects the notification data source based on how the app is running:
///
///  - A backend API configured for this environment (staging/production
///    always; development only when `API_BASE_URL` is set) -> live API
///    repository (API_CONTRACT §21).
///  - Otherwise -> fully local [MockNotificationRepository], so the customer
///    experience never depends on an unfinished backend service.
final notificationsRepositoryProvider = Provider<NotificationRepository>((ref) {
  // In development without an API base URL the mock keeps the notifications
  // screen usable; staging/production always resolve to the live API (per the
  // build-time environment profile), so a mock can never leak into a
  // production build.
  if (EnvConfig.hasApiBaseUrl) {
    return ApiNotificationRepository(ref.watch(apiClientProvider));
  }
  return MockNotificationRepository();
});

final notificationsControllerProvider =
    AsyncNotifierProvider<NotificationsController, List<AppNotification>>(
  NotificationsController.new,
);

/// Derived unread badge count for the shell / app bar.
final unreadCountProvider = Provider<int>((ref) {
  final asyncNotifications = ref.watch(notificationsControllerProvider);
  return (asyncNotifications.value ?? []).where((n) => !n.isRead).length;
});

class NotificationsController extends AsyncNotifier<List<AppNotification>> {
  @override
  Future<List<AppNotification>> build() async {
    // Watch (not read) so login/logout swaps of the repository trigger
    // an automatic reload.
    final repository = ref.watch(notificationsRepositoryProvider);
    return repository.getNotifications();
  }

  /// Reloads from the repository. Used by the error-state retry button.
  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      final repository = ref.read(notificationsRepositoryProvider);
      state = AsyncData(await repository.getNotifications());
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// Optimistically marks one notification as read, then syncs.
  /// A failed sync keeps the optimistic state (idempotent retry later).
  Future<void> markAsRead(String id) async {
    _mutateCurrent((notifications) => [
          for (final n in notifications)
            if (n.id == id && !n.isRead) n.copyWith(isRead: true) else n,
        ]);
    try {
      await ref.read(notificationsRepositoryProvider).markAsRead(id);
    } catch (_) {
      // Optimistic update retained; server catches up on next sync.
    }
  }

  /// Optimistically marks everything as read, then syncs.
  Future<void> markAllAsRead() async {
    _mutateCurrent(
      (notifications) => [
        for (final n in notifications)
          if (!n.isRead) n.copyWith(isRead: true) else n,
      ],
    );
    try {
      await ref.read(notificationsRepositoryProvider).markAllAsRead();
    } catch (_) {
      // Optimistic update retained; server catches up on next sync.
    }
  }

  void _mutateCurrent(
    List<AppNotification> Function(List<AppNotification>) transform,
  ) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(transform(current));
  }
}
