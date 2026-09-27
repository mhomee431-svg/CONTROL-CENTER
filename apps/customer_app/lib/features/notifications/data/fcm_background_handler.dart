import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/security/safe_logger.dart';

/// Storage key for data-only messages that arrived while the app was not
/// running and therefore could not be shown in-app.
const String backgroundMessageQueueKey = 'fcm_background_message_queue_v1';

/// Cap on queued background messages — an old data-only payload must never
/// grow into an unbounded backlog.
const int backgroundMessageQueueLimit = 10;

/// Top-level isolate entry point for FCM messages received while the app
/// is in the background or terminated. Must stay a top-level function.
///
/// Runs in a *separate isolate* with no Riverpod container, no navigator and
/// no BuildContext, so it can do exactly one thing safely: persist.
///
///  * **Notification payload** — the OS already rendered the tray entry and
///    owns the tap (`onMessageOpenedApp` / `getInitialMessage`). Nothing to
///    do; re-showing it here would double-notify the customer.
///  * **Data-only payload** — nothing was displayed at all. Dropping it (as
///    this handler used to) loses the alert permanently, so it is queued on
///    disk and replayed into the in-app surface the next time the customer
///    opens the app.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    SafeLogger.debug(
      'FCM background message ${message.messageId ?? ''} '
      'type=${message.data['type'] ?? ''}',
    );

    // The OS owns anything that already carries a notification block.
    if (message.notification != null) return;
    if (message.data.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final queued = prefs.getStringList(backgroundMessageQueueKey) ?? [];
    queued.add(jsonEncode(message.data));
    if (queued.length > backgroundMessageQueueLimit) {
      queued.removeRange(0, queued.length - backgroundMessageQueueLimit);
    }
    await prefs.setStringList(backgroundMessageQueueKey, queued);
  } catch (error, stackTrace) {
    // Never let a failure here crash the background isolate — the customer
    // would lose every future notification instead of just this one.
    SafeLogger.error('FCM background handler failed', error, stackTrace);
  }
}

/// Drains and clears the persisted background queue.
///
/// Called once at start-up so data-only alerts received while the app was
/// closed are surfaced in-app instead of vanishing. Returns the raw payloads
/// in arrival order; malformed entries are skipped, not fatal.
Future<List<Map<String, dynamic>>> drainBackgroundMessageQueue() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final queued = prefs.getStringList(backgroundMessageQueueKey);
    if (queued == null || queued.isEmpty) return const [];
    await prefs.remove(backgroundMessageQueueKey);

    final messages = <Map<String, dynamic>>[];
    for (final raw in queued) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) messages.add(decoded);
      } catch (_) {
        // Skip a corrupt entry and keep the rest.
      }
    }
    return messages;
  } catch (error, stackTrace) {
    SafeLogger.error('FCM background queue drain failed', error, stackTrace);
    return const [];
  }
}
