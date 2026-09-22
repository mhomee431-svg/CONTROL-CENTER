import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_providers.dart';
import '../domain/notification_models.dart';

/// Notifications contract for one authorized shop.
abstract class NotificationsRepository {
  /// One page of notifications surfaced to the shop's owners/managers.
  ///
  /// Paginated by the BACKEND (`limit` / `offset`): the page carries the
  /// server's own `total`, which is what the screen uses to decide whether a
  /// further page exists. Nothing is loaded twice — the caller passes the
  /// offset of the rows it already holds.
  Future<NotificationsPage> fetchNotifications(
    int shopId,
    String token, {
    int limit,
    int offset,
  });

  /// Marks a single notification as read (idempotent on the backend).
  Future<void> markAsRead(int notificationId, String token);

  /// Marks every notification for this shopkeeper as read (single round
  /// trip; idempotent on the backend).
  Future<void> markAllAsRead(String token);
}

class ApiNotificationsRepository implements NotificationsRepository {
  ApiNotificationsRepository(this._api);

  final ApiClient _api;

  @override
  Future<NotificationsPage> fetchNotifications(
    int shopId,
    String token, {
    int limit = notificationsPageSize,
    int offset = 0,
  }) async {
    final data = await _api.get(
      ApiEndpoints.shopNotifications(shopId),
      token: token,
      query: {'limit': limit, 'offset': offset},
    ) as Map<String, dynamic>;
    return NotificationsPage.fromJson(data);
  }

  @override
  Future<void> markAsRead(int notificationId, String token) async {
    await _api.put(
      ApiEndpoints.notificationRead(notificationId),
      token: token,
      body: const <String, dynamic>{},
    );
  }

  @override
  Future<void> markAllAsRead(String token) async {
    await _api.put(
      ApiEndpoints.notificationsReadAll,
      token: token,
      body: const <String, dynamic>{},
    );
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  return ApiNotificationsRepository(ref.watch(apiClientProvider));
});
