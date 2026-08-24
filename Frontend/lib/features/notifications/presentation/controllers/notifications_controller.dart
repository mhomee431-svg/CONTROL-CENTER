import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/env/env_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../data/api_notification_repository.dart';
import '../../data/mock_notification_repository.dart';
import '../../domain/models/app_notification.dart';
import '../../domain/notification_repository.dart';

/// Selects the notification data source based on how the app is running:
///
///  - Authenticated **and** a backend API is configured -> live API
///    repository (API_CONTRACT §21).
///  - Everyone else (guests, signed-out, or backend not yet deployed) ->
///    fully local [MockNotificationRepository], so the customer
///    experience never depends on the unfinished notification service.
///
/// Watching the auth state means every dependent notifier reloads
/// automatically on login/logout.
final notificationsRepositoryProvider = Provider<NotificationRepository>((ref) {
  final authStatus = ref.watch(authControllerProvider).status;
  if (authStatus == AuthStatus.authenticated && EnvConfig.hasApiBaseUrl) {
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
