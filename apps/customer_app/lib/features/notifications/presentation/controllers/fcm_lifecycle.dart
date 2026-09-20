import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../data/device_token_coordinator.dart';
import '../../data/fcm_notification_service.dart';
import '../../domain/models/app_notification.dart';
import '../controllers/deep_link_handler.dart';
import '../../../settings/presentation/controllers/settings_controller.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';

/// Owns FCM initialize / tap-routing / token-refresh for the app lifetime.
class FcmLifecycle {
  FcmLifecycle(this._ref);

  final Ref _ref;
  StreamSubscription<String>? _tokenSub;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    final service = _ref.read(pushNotificationServiceProvider);
    await service.initialize(onOpened: handleOpenedPayload);
    _tokenSub = service.onTokenRefresh.listen((_) {
      final auth = _ref.read(authControllerProvider);
      if (auth.status != AuthStatus.authenticated) return;
      final settings = _ref.read(settingsControllerProvider);
      unawaited(
        _ref.read(deviceTokenCoordinatorProvider).syncAfterLogin(
              pushEnabled: settings.pushNotificationsEnabled,
            ),
      );
    });
  }

  void handleOpenedPayload(Map<String, dynamic> data) {
    final notification = AppNotification.fromJson({
      'id': data['id']?.toString() ?? '',
      'title': data['title']?.toString() ?? '',
      'body': data['body']?.toString() ?? '',
      'created_at': DateTime.now().toIso8601String(),
      'type': data['type'],
      'payload': data,
      'deep_link': data['deep_link'],
    });
    final resolution = resolveNotificationDeepLink(notification);
    if (resolution.action != DeepLinkAction.navigate) return;
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    GoRouter.of(context).push(resolution.path!);
  }

  Future<void> dispose() async {
    await _tokenSub?.cancel();
  }
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
