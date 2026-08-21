import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../domain/models/app_notification.dart';

/// Real backend implementation for fetching notifications.
class ApiNotificationRepository {
  final ApiClient _apiClient;

  ApiNotificationRepository(this._apiClient);

  Future<List<AppNotification>> getNotifications() async {
    final data = await _apiClient.get(ApiEndpoints.notifications);
    if (data is Map<String, dynamic>) {
      final notifications = data['notifications'] as List<dynamic>? ?? [];
      return notifications.map((e) => _mapNotification(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<void> markAsRead(String id) async {
    await _apiClient.put(ApiEndpoints.notificationRead(id));
  }

  Future<void> markAllAsRead() async {
    await _apiClient.put(ApiEndpoints.notificationsReadAll);
  }

  AppNotification _mapNotification(Map<String, dynamic> json) {
    final typeStr = json['type']?.toString() ?? 'system';
    final type = switch (typeStr) {
      'order_update' => NotificationType.orderUpdate,
      'price_alert' => NotificationType.priceAlert,
      'promotional' => NotificationType.promotional,
      _ => NotificationType.system,
    };

    return AppNotification(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      timestamp: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      isRead: json['is_read'] == true,
      type: type,
      payload: json['payload'] != null ? {'raw': json['payload']} : null,
    );
  }
}