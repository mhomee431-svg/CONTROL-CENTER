import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/device_token_coordinator.dart';
import '../../data/fcm_background_handler.dart';
import '../../data/fcm_notification_service.dart';
import '../../domain/models/app_notification.dart';
import '../controllers/deep_link_handler.dart';
import '../controllers/in_app_notification_controller.dart';
import '../controllers/notification_preferences_controller.dart';
import '../controllers/notifications_controller.dart';
import '../controllers/pending_deep_link_controller.dart';
import '../../../settings/presentation/controllers/settings_controller.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';

/// Owns FCM initialize / tap-routing / token-refresh for the app lifetime.
///
/// ── The three FCM states, and what each one is allowed to do ─────────────
///
/// | State          | Entry point              | Allowed to navigate? |
/// |----------------|--------------------------|----------------------|
/// | Foreground     | `onMessage`              | **No** — in-app only  |
/// | Background tap | `onMessageOpenedApp`     | Queued, then drained |
/// | Terminated tap | `getInitialMessage`      | Queued, then drained |
///
/// Foreground is the only state where the customer is already looking at the
/// app, so it is the only state where navigating unprompted would be rude.
/// Background and terminated taps are explicit intents, but they arrive
/// *before* the router can honour them — so both are queued in
/// [PendingDeepLinkController] and replayed once the launch gates clear,
/// which is what stops the navigation context from being lost.
class FcmLifecycle {
  FcmLifecycle(this._ref);

  final Ref _ref;
  StreamSubscription<String>? _tokenSub;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    final service = _ref.read(pushNotificationServiceProvider);
    await service.initialize(
      onOpened: handleOpenedPayload,
      onForeground: handleForegroundPayload,
    );
    _tokenSub = service.onTokenRefresh.listen((_) {
      final auth = _ref.read(authControllerProvider);
      if (auth.status != AuthStatus.authenticated) return;
      final settings = _ref.read(settingsControllerProvider);
      unawaited(
        _ref
            .read(deviceTokenCoordinatorProvider)
            .syncAfterLogin(pushEnabled: settings.pushNotificationsEnabled),
      );
    });

    // Replay data-only messages that arrived while the app was closed. They
    // were persisted by the background isolate and had no UI to render into,
    // so they are graded and surfaced through the same foreground path.
    unawaited(_replayQueuedBackgroundMessages());
  }

  Future<void> _replayQueuedBackgroundMessages() async {
    final queued = await drainBackgroundMessageQueue();
    for (final payload in queued) {
      handleForegroundPayload(payload);
    }
  }

  /// BACKGROUND / TERMINATED tap.
  ///
  /// Never navigates directly — it validates the link and queues it. The
  /// drain provider replays it as soon as the router is actually able to
  /// route, so a cold start from the notification tray lands the customer on
  /// the intended screen instead of stranding them on the splash screen.
  void handleOpenedPayload(Map<String, dynamic> data) {
    final notification = notificationFromPushPayload(data);
    final resolution = resolveNotificationDeepLink(notification);

    switch (resolution.action) {
      case DeepLinkAction.navigate:
        unawaited(
          _ref
              .read(pendingDeepLinkControllerProvider.notifier)
              .enqueue(resolution.path!, notificationId: notification.id),
        );
      case DeepLinkAction.unavailable:
        // Expired / malformed target. There is no screen to show yet, and no
        // BuildContext this early, so it is simply dropped — the inbox still
        // carries the message and the list tap explains it properly.
        break;
      case DeepLinkAction.none:
        // A message with no target (e.g. a system notice) is still an
        // acknowledgement: mark it read so the badge stays truthful.
        if (notification.id.isNotEmpty) {
          unawaited(
            _ref
                .read(notificationsControllerProvider.notifier)
                .markAsRead(notification.id),
          );
        }
    }
  }

  /// FOREGROUND delivery.
  ///
  /// Grades the message against the customer's own notification settings and
  /// queues it for in-app presentation. The customer keeps doing whatever
  /// they were doing — nothing navigates, nothing is forced.
  void handleForegroundPayload(Map<String, dynamic> data) {
    final notification = notificationFromPushPayload(data);

    final settings = _ref.read(settingsControllerProvider);
    final preferences = _ref
        .read(notificationPreferencesControllerProvider)
        .preferences;
    final presentation = decideInAppPresentation(
      type: notification.type,
      pushEnabled: settings.pushNotificationsEnabled,
      preferences: preferences,
    );
    if (presentation == InAppPresentation.silent) return;

    _ref
        .read(inAppNotificationControllerProvider.notifier)
        .enqueue(notification, presentation: presentation);
  }

  Future<void> dispose() async {
    await _tokenSub?.cancel();
  }
}

/// Builds an [AppNotification] from an FCM data payload.
///
/// Shared by the foreground and tap paths so both grade, icon and deep-link a
/// message identically. The whole `data` map is preserved as the payload
/// because the backend nests the navigation ids inside it.
AppNotification notificationFromPushPayload(Map<String, dynamic> data) {
  return AppNotification.fromJson({
    'id': data['id']?.toString() ?? '',
    'title': data['title']?.toString() ?? '',
    'body': data['body']?.toString() ?? '',
    'created_at': data['created_at']?.toString() ?? '',
    'type': data['type'],
    'payload': data['payload'] ?? data,
    'deep_link': data['deep_link'],
  });
}

final fcmLifecycleProvider = Provider<FcmLifecycle>((ref) {
  final lifecycle = FcmLifecycle(ref);
  ref.onDispose(() {
    unawaited(lifecycle.dispose());
  });
  return lifecycle;
});

final fcmLifecycleBootstrapProvider = Provider<void>((ref) {
  unawaited(ref.watch(fcmLifecycleProvider).start());
});
