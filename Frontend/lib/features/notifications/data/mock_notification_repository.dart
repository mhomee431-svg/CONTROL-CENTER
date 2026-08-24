import '../domain/models/app_notification.dart';
import '../domain/models/device_token_registration.dart';
import '../domain/models/notification_preferences.dart';
import '../domain/notification_repository.dart';

/// Which operation a [MockNotificationRepository] instance should fail.
///
/// Used by widget/controller tests to exercise error states without any
/// networking. Defaults to [MockFailureMode.none].
enum MockFailureMode { none, load, markRead, preferences }

/// Fully local implementation of [NotificationRepository].
///
/// Keeps an in-memory store so read/unread state and preference changes
/// survive across provider rebuilds within a session, letting the whole
/// customer notification experience run before the backend exists.
class MockNotificationRepository implements NotificationRepository {
  /// When non-`none`, the matching operation throws instead of succeeding.
  final MockFailureMode failureMode;

  /// Artificial latency; pass [Duration.zero] in widget tests running
  /// under fake-async time where real timers never fire.
  final Duration delay;

  final List<AppNotification> _store;
  NotificationPreferences _preferences;
  final Map<String, bool> _registeredTokens = {};

  MockNotificationRepository({
    this.failureMode = MockFailureMode.none,
    this.delay = const Duration(milliseconds: 150),
    List<AppNotification>? seed,
    NotificationPreferences? preferences,
  })  : _store = seed != null
            ? List.of(seed)
            : List.of(_defaultSeed(now: DateTime.now())),
        _preferences = preferences ?? NotificationPreferences.defaults;

  Future<void> _pause() async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
  }

  /// Demo dataset covering every customer-facing type, deep-link targets
  /// (product / shop / expired offer) and mixed read state.
  static List<AppNotification> _defaultSeed({required DateTime now}) => [
        AppNotification(
          id: 'n1',
          title: 'Price drop alert',
          body: 'Samsung Galaxy S24 is now ₹25.50 less at Gupta Electronics!',
          timestamp: now.subtract(const Duration(hours: 2)),
          type: NotificationType.priceDrop,
          deepLink: const NotificationDeepLink(
            targetType: DeepLinkTargetType.product,
            targetId: 'prod_1',
          ),
        ),
        AppNotification(
          id: 'n2',
          title: 'Back in stock',
          body: 'Paracetamol 500mg is available again at Patna Medical Store.',
          timestamp: now.subtract(const Duration(hours: 5)),
          type: NotificationType.productAvailable,
          deepLink: const NotificationDeepLink(
            targetType: DeepLinkTargetType.product,
            targetId: 'prod_2',
          ),
        ),
        AppNotification(
          id: 'n3',
          title: 'Flat 20% off today',
          body: 'Digital World Hub is running a monsoon deal on accessories.',
          timestamp: now.subtract(const Duration(hours: 26)),
          type: NotificationType.offer,
          deepLink: NotificationDeepLink(
            targetType: DeepLinkTargetType.offer,
            targetId: 'offer_9',
            // Already ended -> tapping must degrade safely.
            expiresAt: now.subtract(const Duration(hours: 1)),
          ),
        ),
        AppNotification(
          id: 'n4',
          title: 'Gupta Electronics updated timings',
          body: 'Now open until 10 PM on weekdays.',
          timestamp: now.subtract(const Duration(days: 2)),
          type: NotificationType.shopUpdate,
          deepLink: const NotificationDeepLink(
            targetType: DeepLinkTargetType.shop,
            targetId: 'shop_3',
          ),
        ),
        AppNotification(
          id: 'n5',
          title: 'Welcome to Hyperlocal',
          body: 'Your account is ready. Discover shops around you!',
          timestamp: now.subtract(const Duration(days: 3)),
          isRead: true,
          type: NotificationType.system,
        ),
      ];

  @override
  Future<List<AppNotification>> getNotifications() async {
    await _pause();
    if (failureMode == MockFailureMode.load) {
      throw Exception('Mock notification load failure');
    }
    return List.of(_store);
  }

  @override
  Future<void> markAsRead(String id) async {
    await _pause();
    if (failureMode == MockFailureMode.markRead) {
      throw Exception('Mock mark-as-read failure');
    }
    for (var i = 0; i < _store.length; i++) {
      if (_store[i].id == id && !_store[i].isRead) {
        _store[i] = _store[i].copyWith(isRead: true);
        return;
      }
    }
  }

  @override
  Future<void> markAllAsRead() async {
    await _pause();
    if (failureMode == MockFailureMode.markRead) {
      throw Exception('Mock mark-all-read failure');
    }
    for (var i = 0; i < _store.length; i++) {
      if (!_store[i].isRead) _store[i] = _store[i].copyWith(isRead: true);
    }
  }

  @override
  Future<NotificationPreferences> getPreferences() async {
    await _pause();
    if (failureMode == MockFailureMode.preferences) {
      throw Exception('Mock preferences failure');
    }
    return _preferences;
  }

  @override
  Future<void> updatePreferences(NotificationPreferences preferences) async {
    await _pause();
    if (failureMode == MockFailureMode.preferences) {
      throw Exception('Mock preferences failure');
    }
    _preferences = preferences;
  }

  @override
  Future<void> registerDeviceToken(DeviceTokenRegistration registration) async {
    await _pause();
    if (failureMode == MockFailureMode.preferences) {
      throw Exception('Mock device-token registration failure');
    }
    _registeredTokens[registration.token] = true;
  }

  @override
  Future<void> unregisterDeviceToken(String token) async {
    await _pause();
    if (failureMode == MockFailureMode.preferences) {
      throw Exception('Mock device-token unregistration failure');
    }
    _registeredTokens.remove(token);
  }

  /// Exposed for assertions in tests only.
  bool isTokenRegistered(String token) => _registeredTokens[token] ?? false;
}
