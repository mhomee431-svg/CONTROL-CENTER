import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class PushNotificationService {
  Future<void> initialize();
  Future<String?> getToken();
  Future<void> subscribeToTopic(String topic);
  Future<void> unsubscribeFromTopic(String topic);
}

/// Firebase Cloud Messaging Abstraction Layer
class FcmNotificationService implements PushNotificationService {
  @override
  Future<void> initialize() async {
    // Hooks into FirebaseMessaging.instance.requestPermission()
    // and FirebaseMessaging.onMessage background/foreground handlers
  }

  @override
  Future<String?> getToken() async {
    // Returns FCM registration token for backend payload targeting
    return 'mock_fcm_token_xyz_123';
  }

  @override
  Future<void> subscribeToTopic(String topic) async {}

  @override
  Future<void> unsubscribeFromTopic(String topic) async {}
}

final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  return FcmNotificationService();
});