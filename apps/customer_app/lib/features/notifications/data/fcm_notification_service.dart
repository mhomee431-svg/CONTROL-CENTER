import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/env/env_config.dart';
import '../../../core/security/safe_logger.dart';
import 'fcm_background_handler.dart';

typedef PushOpenedCallback = void Function(Map<String, dynamic> data);

abstract class PushNotificationService {
  Future<void> initialize({PushOpenedCallback? onOpened});
  Future<String?> getToken();
  Future<void> subscribeToTopic(String topic);
  Future<void> unsubscribeFromTopic(String topic);
  Stream<String> get onTokenRefresh;
}

/// In-memory stand-in used for mock/dev builds and widget tests so FCM is
/// never a hard dependency when Firebase is not initialized.
class MockFcmNotificationService implements PushNotificationService {
  MockFcmNotificationService({this.token = 'mock_fcm_token_xyz_123'});

  final String token;
  final StreamController<String> _tokenRefresh =
      StreamController<String>.broadcast();

  @override
  Future<void> initialize({PushOpenedCallback? onOpened}) async {}

  @override
  Future<String?> getToken() async => token;

  @override
  Future<void> subscribeToTopic(String topic) async {}

  @override
  Future<void> unsubscribeFromTopic(String topic) async {}

  @override
  Stream<String> get onTokenRefresh => _tokenRefresh.stream;
}

/// Firebase Cloud Messaging implementation: permission, token, topic
/// subscribe, token refresh, and notification-tap routing.
class FcmNotificationService implements PushNotificationService {
  FcmNotificationService({FirebaseMessaging? messaging})
      : _injected = messaging;

  final FirebaseMessaging? _injected;
  final StreamController<String> _tokenRefresh =
      StreamController<String>.broadcast();

  FirebaseMessaging? _messaging;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  bool _initialized = false;

  FirebaseMessaging? get _instance {
    if (_injected != null) return _injected;
    if (Firebase.apps.isEmpty) return null;
    return FirebaseMessaging.instance;
  }

  @override
  Future<void> initialize({PushOpenedCallback? onOpened}) async {
    if (_initialized) return;
    final messaging = _instance;
    if (messaging == null) return;
    _messaging = messaging;
    _initialized = true;

    try {
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        announcement: false,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
      );
    } catch (e, stack) {
      SafeLogger.error('FCM permission request failed', e, stack);
    }

    _tokenSub = messaging.onTokenRefresh.listen(_tokenRefresh.add);

    if (onOpened != null) {
      try {
        final initial = await messaging.getInitialMessage();
        if (initial != null) {
          onOpened(_messageData(initial));
        }
      } catch (e, stack) {
        SafeLogger.error('FCM initial message failed', e, stack);
      }

      _openedSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
        onOpened(_messageData(message));
      });

      _foregroundSub = FirebaseMessaging.onMessage.listen((message) {
        SafeLogger.debug(
          'FCM foreground message ${message.messageId ?? ''}',
        );
      });
    }
  }

  Map<String, dynamic> _messageData(RemoteMessage message) {
    return {
      ...message.data,
      'title': message.notification?.title ?? message.data['title'],
      'body': message.notification?.body ?? message.data['body'],
      'id': message.messageId ?? message.data['id'] ?? '',
    };
  }

  @override
  Future<String?> getToken() async {
    try {
      final messaging = _messaging ?? _instance;
      if (messaging == null) return null;
      return await messaging.getToken();
    } catch (e, stack) {
      SafeLogger.error('FCM getToken failed', e, stack);
      return null;
    }
  }

  @override
  Future<void> subscribeToTopic(String topic) async {
    if (topic.trim().isEmpty) return;
    try {
      final messaging = _messaging ?? _instance;
      await messaging?.subscribeToTopic(topic);
    } catch (e, stack) {
      SafeLogger.error('FCM subscribeToTopic failed', e, stack);
    }
  }

  @override
  Future<void> unsubscribeFromTopic(String topic) async {
    if (topic.trim().isEmpty) return;
    try {
      final messaging = _messaging ?? _instance;
      await messaging?.unsubscribeFromTopic(topic);
    } catch (e, stack) {
      SafeLogger.error('FCM unsubscribeFromTopic failed', e, stack);
    }
  }

  @override
  Stream<String> get onTokenRefresh => _tokenRefresh.stream;

  Future<void> dispose() async {
    await _tokenSub?.cancel();
    await _openedSub?.cancel();
    await _foregroundSub?.cancel();
    await _tokenRefresh.close();
  }
}

final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  if (!EnvConfig.hasApiBaseUrl || Firebase.apps.isEmpty) {
    return MockFcmNotificationService();
  }
  return FcmNotificationService();
});

/// Registers the background handler. Call once from [main] after Firebase
/// has been initialized. Safe to skip when Firebase is not configured.
void registerFcmBackgroundHandler() {
  if (Firebase.apps.isEmpty) return;
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
}
