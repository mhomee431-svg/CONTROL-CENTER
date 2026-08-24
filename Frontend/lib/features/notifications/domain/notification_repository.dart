import 'models/app_notification.dart';
import 'models/device_token_registration.dart';
import 'models/notification_preferences.dart';

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
