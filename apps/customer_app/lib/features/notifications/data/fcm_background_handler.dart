import 'package:firebase_messaging/firebase_messaging.dart';

import '../../../core/security/safe_logger.dart';

/// Top-level isolate entry point for FCM messages received while the app
/// is in the background or terminated. Must stay a top-level function.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  SafeLogger.debug(
    'FCM background message ${message.messageId ?? ''} '
    'type=${message.data['type'] ?? ''}',
  );
}
