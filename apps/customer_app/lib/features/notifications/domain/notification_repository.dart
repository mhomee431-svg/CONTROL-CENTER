import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/env/env_config.dart';
import '../../../../core/network/api_client.dart';
import '../data/api_notification_repository.dart';
import '../data/mock_notification_repository.dart';
import 'models/app_notification.dart';
import 'models/device_token_registration.dart';
import 'models/notification_preferences.dart';

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

/// Abstract contract for everything notification-related.
///
/// Implementations:
///  - [ApiNotificationRepository] – live backend (API_CONTRACT §21)
///  - [MockNotificationRepository] – local/demo data so the customer
///    experience works before the notification service ships.
///
/// The UI only ever depends on this interface; delivery mechanics
/// (FCM/APNS registration, topic subscriptions) are handled by
/// [PushNotificationService]/[DeviceTokenCoordinator], never by screens.
abstract class NotificationRepository {
  /// Latest notifications for the customer, newest first.
  Future<List<AppNotification>> getNotifications();

  /// Idempotently marks a single notification as read.
  Future<void> markAsRead(String id);

  /// Idempotently marks every notification as read.
  Future<void> markAllAsRead();

  /// Current per-channel/per-type delivery preferences.
  Future<NotificationPreferences> getPreferences();

  /// Persists new delivery preferences. Idempotent.
  Future<void> updatePreferences(NotificationPreferences preferences);

  /// Registers this device's push token with the backend (no-op when the
  /// same token was already registered — idempotent per contract).
  Future<void> registerDeviceToken(DeviceTokenRegistration registration);

  /// Removes this device's push token (e.g. on logout). Idempotent.
  Future<void> unregisterDeviceToken(String token);
}
