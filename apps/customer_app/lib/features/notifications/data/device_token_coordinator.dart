import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/secure_storage_service.dart';
import '../../auth/domain/auth_service.dart' show authAppVersion;
import '../domain/models/device_token_registration.dart';
import '../domain/notification_repository.dart';
import '../presentation/controllers/notifications_controller.dart'
    show notificationsRepositoryProvider;
import 'fcm_notification_service.dart';

/// Coordinates device push-token registration with the backend notification
/// service.
///
/// Responsibilities (all best-effort, never blocking the UI):
///  - obtain the platform token from [PushNotificationService]
///  - register it with the backend once per token change
///  - unregister it on logout
///
/// When Firebase is not initialized (mock/dev), [MockFcmNotificationService]
/// supplies a local token so registration stays exercisable in tests.
class DeviceTokenCoordinator {
  static const lastRegisteredTokenKey = 'registered_device_token';

  final Ref _ref;

  DeviceTokenCoordinator(this._ref);

  /// Called after a successful login / on app start while authenticated.
  ///
  /// Registers the current device token when it changed since the last
  /// successful registration. When push is disabled at the app level the
  /// token is unregistered instead so the backend stops targeting this
  /// device.
  Future<void> syncAfterLogin({required bool pushEnabled}) async {
    try {
      final storage = _ref.read(secureStorageProvider);
      final pushService = _ref.read(pushNotificationServiceProvider);
      final NotificationRepository repository =
          _ref.read(notificationsRepositoryProvider);

      if (!pushEnabled) {
        await _unregisterExisting(storage, repository);
        return;
      }

      final token = await pushService.getToken();
      if (token == null || token.isEmpty) return;

      final lastToken = await storage.read(key: lastRegisteredTokenKey);
      if (lastToken == token) return; // already registered — idempotent

      await repository.registerDeviceToken(
        DeviceTokenRegistration(
          token: token,
          deviceType: _deviceType(),
          platform: 'FCM',
          appVersion: authAppVersion,
        ),
      );
      await storage.write(key: lastRegisteredTokenKey, value: token);
    } catch (_) {
      // Best effort — retried on next login / app start.
    }
  }

  /// Called on logout. Removes the backend registration and clears the
  /// local marker so a later login registers fresh.
  Future<void> handleLogout() async {
    try {
      final storage = _ref.read(secureStorageProvider);
      final NotificationRepository repository =
          _ref.read(notificationsRepositoryProvider);
      await _unregisterExisting(storage, repository);
    } catch (_) {
      // Best effort.
    }
  }

  Future<void> _unregisterExisting(
    SecureStorageService storage,
    NotificationRepository repository,
  ) async {
    final lastToken = await storage.read(key: lastRegisteredTokenKey);
    if (lastToken == null || lastToken.isEmpty) return;
    try {
      await repository.unregisterDeviceToken(lastToken);
    } finally {
      await storage.delete(key: lastRegisteredTokenKey);
    }
  }

  String _deviceType() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return 'android';
    }
  }
}

final deviceTokenCoordinatorProvider = Provider<DeviceTokenCoordinator>(
  (ref) => DeviceTokenCoordinator(ref),
);

