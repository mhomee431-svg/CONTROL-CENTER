import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/errors/app_message_code.dart';
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
    this.total = 0,
    this.loadingMore = false,
    this.message,
  });

  final NotificationsStatus status;
  final List<ShopkeeperNotification> items;
  final int unreadCount;

  /// How many notifications this shop has in total, per the SERVER's count
  /// across every page — not the number currently held.
  final int total;

  /// True while the next page is in flight (the footer shows progress).
  final bool loadingMore;

  /// Error copy when [status] is [NotificationsStatus.error].
  final String? message;

  /// True when the server holds rows this list has not fetched yet.
  ///
  /// Derived from the server's own [total] and the rows in hand, so it can
  /// never promise a page that does not exist.
  bool get hasMore => items.length < total;

  /// Rows still behind the page break — the count the footer offers.
  int get hidden => total - items.length;

  factory NotificationsState.loading() =>
      const NotificationsState(status: NotificationsStatus.loading);

  NotificationsState copyWith({
    NotificationsStatus? status,
    List<ShopkeeperNotification>? items,
    int? unreadCount,
    int? total,
    bool? loadingMore,
    String? message,
  }) =>
      NotificationsState(
        status: status ?? this.status,
        items: items ?? this.items,
        unreadCount: unreadCount ?? this.unreadCount,
        total: total ?? this.total,
        loadingMore: loadingMore ?? this.loadingMore,
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

  /// Loads (or reloads) the FIRST page for the selected shop.
  ///
  /// A reload always restarts at offset 0 and replaces the rows: the list must
  /// never show page 2 of a previous session's data stacked under page 1 of the
  /// current one.
  Future<void> load() async {
    final shopId = _shopId;
    if (shopId == null) {
      state = const NotificationsState(status: NotificationsStatus.ready);
      return;
    }
    state = NotificationsState.loading();
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw ApiException.localized(AppMessageCode.notSignedIn);
      final page = await _repo.fetchNotifications(
        shopId,
        token,
        limit: notificationsPageSize,
      );
      state = NotificationsState(
        status: NotificationsStatus.ready,
        items: page.items,
        unreadCount: page.unreadCount,
        total: page.total,
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

  /// Fetches the NEXT page and appends it.
  ///
  /// Backend pagination, not a wider request: the offset is the number of rows
  /// already held, so each page costs one bounded round trip and no row is
  /// downloaded twice. Safe to call when nothing is left — the guard returns
  /// immediately, so a footer tap at the end of the list cannot loop.
  Future<void> loadMore() async {
    final shopId = _shopId;
    if (shopId == null) return;
    if (state.status != NotificationsStatus.ready) return;
    if (!state.hasMore || state.loadingMore) return;

    state = state.copyWith(loadingMore: true);
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw ApiException.localized(AppMessageCode.notSignedIn);
      final page = await _repo.fetchNotifications(
        shopId,
        token,
        limit: notificationsPageSize,
        offset: state.items.length,
      );
      // De-duplicate by id: a notification arriving mid-page shifts the
      // offset window, and the same row could otherwise be listed twice.
      final seen = state.items.map((n) => n.id).toSet();
      state = state.copyWith(
        items: [
          ...state.items,
          ...page.items.where((n) => !seen.contains(n.id)),
        ],
        unreadCount: page.unreadCount,
        total: page.total,
        loadingMore: false,
      );
    } on ApiException catch (e) {
      // Keep the rows already loaded — a failed page must not blank the list.
      state = state.copyWith(loadingMore: false, message: e.message);
    } catch (_) {
      state = state.copyWith(
        loadingMore: false,
        message: 'Could not load more notifications.',
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
            payload: n.payload,
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
            payload: n.payload,
          ),
      ],
      unreadCount: 0,
    );

    try {
      // Single round trip — the backend marks every owned row read at once.
      await _repo.markAllAsRead(token);
    } on ApiException {
      await load(); // restore the real state from the backend
    }
  }

  /// Clears ALL cached notifications (called on logout) so nothing from the
  /// previous account survives into the next session.
  void reset() => state = NotificationsState.loading();
}
