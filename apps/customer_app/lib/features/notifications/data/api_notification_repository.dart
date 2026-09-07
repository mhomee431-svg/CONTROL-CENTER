import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../domain/models/app_notification.dart';
import '../domain/models/device_token_registration.dart';
import '../domain/models/notification_preferences.dart';
import '../domain/notification_repository.dart';

/// Real backend implementation of [NotificationRepository]
/// (API_CONTRACT §21). The backend service is not finished yet — the
/// repository provider only selects this class once the user is
/// authenticated AND the API base URL is configured.
class ApiNotificationRepository implements NotificationRepository {
  final ApiClient _apiClient;

  ApiNotificationRepository(this._apiClient);

  @override
  Future<List<AppNotification>> getNotifications() async {
    final data = await _apiClient.get(ApiEndpoints.notifications);
    if (data is Map<String, dynamic>) {
      final notifications = data['notifications'] as List<dynamic>? ?? [];
      return notifications
          .whereType<Map<String, dynamic>>()
          .map(AppNotification.fromJson)
          .toList();
    }
    return [];
  }

  @override
  Future<void> markAsRead(String id) async {
    await _apiClient.put(ApiEndpoints.notificationRead(id));
  }

  @override
  Future<void> markAllAsRead() async {
    await _apiClient.put(ApiEndpoints.notificationsReadAll);
  }

  @override
  Future<NotificationPreferences> getPreferences() async {
    final data = await _apiClient.get(ApiEndpoints.notificationPreferences);
    if (data is Map<String, dynamic>) {
      return NotificationPreferences.fromApiJson(data);
    }
    return NotificationPreferences.defaults;
  }

  @override
  Future<void> updatePreferences(NotificationPreferences preferences) async {
    await _apiClient.put(
      ApiEndpoints.notificationPreferences,
      data: preferences.toApiJson(),
    );
  }

  @override
  Future<void> registerDeviceToken(DeviceTokenRegistration registration) async {
    await _apiClient.post(
      ApiEndpoints.registerDeviceToken,
      data: registration.toJson(),
    );
  }

  @override
  Future<void> unregisterDeviceToken(String token) async {
    await _apiClient.delete(ApiEndpoints.unregisterDeviceToken(token));
  }
}
