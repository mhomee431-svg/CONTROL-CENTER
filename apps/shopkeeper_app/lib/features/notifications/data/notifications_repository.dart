import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_providers.dart';
import '../domain/notification_models.dart';

/// Notifications contract for one authorized shop.
abstract class NotificationsRepository {
  /// Latest notifications surfaced to the shop's owners/managers.
  Future<NotificationsPage> fetchNotifications(
      int shopId, String token, {int limit});

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
    int limit = 50,
  }) async {
    final data = await _api.get(
      ApiEndpoints.shopNotifications(shopId),
      token: token,
      query: {'limit': limit},
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
