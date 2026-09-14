import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/token_store.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../data/notifications_repository.dart';
import '../../domain/notification_models.dart';

enum NotificationsStatus { loading, ready, error }

class NotificationsState {
  const NotificationsState({
    required this.status,
    this.items = const [],
    this.unreadCount = 0,
    this.message,
  });

  final NotificationsStatus status;
  final List<ShopkeeperNotification> items;
  final int unreadCount;

  /// Error copy when [status] is [NotificationsStatus.error].
  final String? message;

  factory NotificationsState.loading() =>
      const NotificationsState(status: NotificationsStatus.loading);

  NotificationsState copyWith({
    NotificationsStatus? status,
    List<ShopkeeperNotification>? items,
    int? unreadCount,
    String? message,
  }) =>
      NotificationsState(
        status: status ?? this.status,
        items: items ?? this.items,
        unreadCount: unreadCount ?? this.unreadCount,
        message: message,
      );
}

final notificationsControllerProvider =
    NotifierProvider<NotificationsController, NotificationsState>(
        NotificationsController.new);

class NotificationsController extends Notifier<NotificationsState> {
  @override
  NotificationsState build() => NotificationsState.loading();

  NotificationsRepository get _repo => ref.read(notificationsRepositoryProvider);

  int? get _shopId => ref.read(selectedShopProvider)?.id;

  /// Loads (or reloads) the notifications for the selected shop.
  Future<void> load() async {
    final shopId = _shopId;
    if (shopId == null) {
      state = const NotificationsState(status: NotificationsStatus.ready);
      return;
    }
    state = NotificationsState.loading();
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      final page = await _repo.fetchNotifications(shopId, token);
      state = NotificationsState(
        status: NotificationsStatus.ready,
        items: page.items,
        unreadCount: page.unreadCount,
      );
    } on ApiException catch (e) {
      state = NotificationsState(
        status: NotificationsStatus.error,
        message: e.isForbidden
            ? 'You do not have access to notifications for this shop.'
            : e.message,
      );
    } catch (_) {
      state = const NotificationsState(
        status: NotificationsStatus.error,
        message: 'Could not load notifications.',
      );
    }
  }

  /// Marks one notification as read (optimistic UI, server-confirmed).
  Future<void> markAsRead(int notificationId) async {
    final token = await ref.read(tokenStoreProvider).readAccessToken();
    if (token == null) return;

    // Optimistic update — the list re-renders immediately.
    final updated = [
      for (final n in state.items)
        if (n.id == notificationId && n.isUnread)
          ShopkeeperNotification(
            id: n.id,
            title: n.title,
            body: n.body,
            type: n.type,
            isRead: true,
            createdAt: n.createdAt,
            deepLink: n.deepLink,
          )
        else
          n,
    ];
    final unreadDelta = state.items.any(
            (n) => n.id == notificationId && n.isUnread)
        ? 1
        : 0;
    final newUnread = state.unreadCount - unreadDelta;
    state = state.copyWith(
      items: updated,
      unreadCount: newUnread < 0 ? 0 : newUnread,
    );

    try {
      await _repo.markAsRead(notificationId, token);
    } on ApiException {
      // Roll back on failure so the badge stays honest.
      await load();
    }
  }

  /// Marks every notification as read.
  Future<void> markAllAsRead() async {
    final unread = state.items.where((n) => n.isUnread).toList(growable: false);
    if (unread.isEmpty) return;
    final token = await ref.read(tokenStoreProvider).readAccessToken();
    if (token == null) return;

    // Optimistic: all read, badge zeroed.
    state = state.copyWith(
      items: [
        for (final n in state.items)
          ShopkeeperNotification(
            id: n.id,
            title: n.title,
            body: n.body,
            type: n.type,
            isRead: true,
            createdAt: n.createdAt,
            deepLink: n.deepLink,
          ),
      ],
      unreadCount: 0,
    );

    var failed = false;
    for (final n in unread) {
      try {
        await _repo.markAsRead(n.id, token);
      } on ApiException {
        failed = true;
        break;
      }
    }
    if (failed) await load(); // restore the real state from the backend
  }

  /// Clears ALL cached notifications (called on logout) so nothing from the
  /// previous account survives into the next session.
  void reset() => state = NotificationsState.loading();
}
