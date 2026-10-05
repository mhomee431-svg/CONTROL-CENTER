import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Locks the FCM registration-token contract across client and backend.
///
/// Every way this flow breaks is invisible at runtime: the token stops being
/// registered and notifications simply stop arriving. No crash, no error, no
/// failing test. A rename on either side of the wire also compiles perfectly.
///
/// So this checks the links FCM's own documentation says matter: the client has
/// an endpoint, the backend serves that path, the client subscribes to
/// `onTokenRefresh` (registration tokens DO change), a refresh re-registers, and
/// a logout unregisters.
///
/// The backend is a sibling package rather than a Dart dependency, so its checks
/// SKIP when the tree is absent instead of failing: a partial checkout is not
/// evidence of a broken contract.
void main() {
  final backendRoot = Directory(r'..\..\backend');
  final backendPresent = backendRoot.existsSync();

  String? _findIn(String dir, String name) {
    final root = Directory(dir);
    if (!root.existsSync()) return null;
    for (final f in root.listSync(recursive: true).whereType<File>()) {
      if (f.path.endsWith(name)) return f.readAsStringSync();
    }
    return null;
  }

  /// Source of a client file, or null when it has been renamed away.
  String? client(String name) => _findIn('lib', name);

  /// The backend notifications router, or null when unavailable.
  String? backendRouter() =>
      backendPresent ? _findIn(r'..\..\backend', 'notifications.py') : null;

  group('the client can reach a device-token endpoint', () {
    test('ApiEndpoints declares the register path', () {
      final endpoints = File('lib/core/network/api_endpoints.dart')
          .readAsStringSync();
      expect(endpoints, contains('device-token'));
    });

    test('the repository implements both calls', () {
      final source = client('api_notification_repository.dart');
      expect(
        source,
        isNotNull,
        reason: 'ApiNotificationRepository renamed away',
      );
      expect(source, contains('registerDeviceToken'));
      expect(source, contains('unregisterDeviceToken'));
    });
  });

  group('the backend serves those exact paths', () {
    test('FastAPI exposes POST and DELETE /device-token', () {
      final router = backendRouter();
      if (router == null) {
        markTestSkipped('backend tree not present in this checkout');
        return;
      }
      expect(
        router,
        contains('@router.post("/device-token")'),
        reason: 'the client POSTs to /notifications/device-token',
      );
      expect(
        router,
        contains('@router.delete("/device-token/{token}")'),
        reason: 'the client DELETEs to /notifications/device-token/{token}',
      );
    });

    test('registration ties a token to a user and can deactivate it', () {
      // Two people sharing a device get the SAME token, so registration must
      // reassign ownership rather than add a row or keep the first owner.
      final router = backendRouter();
      if (router == null) {
        markTestSkipped('backend tree not present in this checkout');
        return;
      }
      expect(router, contains('user_id'));
      expect(router, contains('is_active'));
    });

    test('the device_tokens table enforces one row per token', () {
      // Without this a retried registration duplicates the row and a send can
      // fan out twice to the same handset.
      if (!backendPresent) {
        markTestSkipped('backend tree not present in this checkout');
        return;
      }
      var found = false;
      for (final f in backendRoot.listSync(recursive: true).whereType<File>()) {
        if (f.path.endsWith('.py') &&
            f.readAsStringSync().contains('uq_device_tokens_token')) {
          found = true;
        }
      }
      expect(found, isTrue);
    });
  });

  group('the client handles token refresh, as FCM requires', () {
    // FCM registration tokens change on app restore, reinstall and rotation.
    // A client that reads the token once silently stops receiving push.
    test('the service wires the real platform refresh stream', () {
      final source = client('fcm_notification_service.dart');
      expect(source, isNotNull);
      expect(source, contains('onTokenRefresh'));
      expect(
        source,
        contains('messaging.onTokenRefresh'),
        reason: 'it must be wired to the real FCM stream, not just declared',
      );
    });

    test('the lifecycle re-registers when the token rotates', () {
      final source = client('fcm_lifecycle.dart');
      expect(source, isNotNull);
      expect(
        source,
        contains('onTokenRefresh.listen'),
        reason: 'a refresh nobody listens to is the exact FCM failure mode',
      );
      expect(source, contains('syncAfterLogin'));
    });

    test('logout unregisters, so a token cannot outlive its session', () {
      final coordinator = client('device_token_coordinator.dart');
      expect(coordinator, isNotNull);
      expect(coordinator, contains('handleLogout'));
      expect(coordinator, contains('unregisterDeviceToken'));
      expect(
        File('lib/app.dart').readAsStringSync(),
        contains('handleLogout'),
        reason: 'the coordinator must run from the auth transition',
      );
    });

    test('the dedup marker stays a named constant', () {
      final coordinator = client('device_token_coordinator.dart');
      expect(
        coordinator,
        contains('lastRegisteredTokenKey'),
        reason: 'a renamed marker would orphan registered tokens',
      );
    });
  });
}
