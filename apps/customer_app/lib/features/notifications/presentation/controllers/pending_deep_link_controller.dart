import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/local_storage_driver.dart';

/// Storage key for the deep link that arrived before the app was able to
/// route it (cold start from a terminated-state notification tap).
const String pendingDeepLinkStorageKey = 'pending_notification_deep_link_v1';

/// How long a queued deep link stays actionable.
///
/// A tap that opens a notification tray entry from three hours ago must not
/// yank the customer into a product page the moment they launch the app.
/// Past this window the link is dropped and only the inbox entry survives.
const Duration pendingDeepLinkTtl = Duration(minutes: 15);

/// A deep link that has been validated but could not be opened yet because
/// the router was still gated behind splash / onboarding / auth resolution.
@immutable
class PendingDeepLink {
  final String path;

  /// Notification the link came from, so the inbox can be marked read.
  final String notificationId;

  final DateTime queuedAt;

  const PendingDeepLink({
    required this.path,
    required this.notificationId,
    required this.queuedAt,
  });

  /// Whether the link is still fresh enough to act on.
  bool isExpired({DateTime? now, Duration ttl = pendingDeepLinkTtl}) =>
      (now ?? DateTime.now()).difference(queuedAt) > ttl;

  Map<String, dynamic> toJson() => {
    'path': path,
    'notification_id': notificationId,
    'queued_at': queuedAt.toIso8601String(),
  };

  /// Tolerant of corrupt/partial storage — returns null rather than throwing
  /// so a bad write can never brick app start.
  static PendingDeepLink? fromJson(Map<String, dynamic> json) {
    final path = json['path']?.toString() ?? '';
    if (path.isEmpty) return null;
    final queuedAt =
        DateTime.tryParse(json['queued_at']?.toString() ?? '') ?? DateTime.now();
    return PendingDeepLink(
      path: path,
      notificationId: json['notification_id']?.toString() ?? '',
      queuedAt: queuedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PendingDeepLink &&
      other.path == path &&
      other.notificationId == notificationId &&
      other.queuedAt == queuedAt;

  @override
  int get hashCode => Object.hash(path, notificationId, queuedAt);
}

/// Holds the deep link from a notification tap until the router is allowed
/// to act on it.
///
/// A tap reaches the app through three different FCM entry points, and two
/// of them fire *before the app can navigate anywhere*:
///
///  * **terminated state** — `getInitialMessage()` resolves during
///    `FirebaseMessaging` initialization, while the first frame is still
///    being built. The router is parked on `/splash` behind the
///    `AuthStatus.initial` and `onboardingCompleted == null` gates, so
///    navigating immediately either throws (no navigator yet) or is bounced
///    straight back to `/splash` by the redirect — silently losing the tap.
///  * **background** — `onMessageOpenedApp()` fires on resume, which can
///    still overlap a token refresh or a router rebuild.
///
/// Taps are therefore never navigated directly. They are *queued* here,
/// persisted across process death, and replayed only once the launch gates
/// clear. That is what makes the navigation context survive start-up.
class PendingDeepLinkController extends Notifier<PendingDeepLink?> {
  @override
  PendingDeepLink? build() {
    // Restore on construction: a link queued by a previous process (the
    // terminated-state case) must not be lost just because this run starts
    // fresh.
    Future.microtask(restore);
    return null;
  }

  /// Queues a deep link, replacing any earlier one.
  ///
  /// Only the newest tap survives: replaying a stale link over a fresh one
  /// would send the customer somewhere they already declined to go.
  Future<void> enqueue(String path, {String notificationId = ''}) async {
    if (path.isEmpty) return;
    final link = PendingDeepLink(
      path: path,
      notificationId: notificationId,
      queuedAt: DateTime.now(),
    );
    state = link;
    await _persist(link);
  }

  /// Removes and returns the queued link, or null when there is nothing
  /// actionable. Expired links are discarded rather than replayed.
  PendingDeepLink? take({DateTime? now}) {
    final link = state;
    if (link == null) return null;
    state = null;
    unawaited(_persist(null));
    if (link.isExpired(now: now)) return null;
    return link;
  }

  /// Reads back a link persisted by a previous run. Never overrides a link
  /// that was queued moments ago in *this* run.
  Future<void> restore() async {
    try {
      final raw = await ref
          .read(localStorageDriverProvider)
          .getString(pendingDeepLinkStorageKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final link = PendingDeepLink.fromJson(decoded);
      // Drop anything that aged out while the app was not running.
      if (link == null || link.isExpired()) {
        await _persist(null);
        return;
      }
      if (state == null) state = link;
    } catch (_) {
      // Corrupt payload — drop it, never block start-up on it.
      await _persist(null);
    }
  }

  Future<void> _persist(PendingDeepLink? link) async {
    try {
      final storage = ref.read(localStorageDriverProvider);
      if (link == null) {
        await storage.remove(pendingDeepLinkStorageKey);
      } else {
        await storage.setString(
          pendingDeepLinkStorageKey,
          jsonEncode(link.toJson()),
        );
      }
    } catch (_) {
      // Persistence is best-effort; the in-memory queue still works.
    }
  }
}

final pendingDeepLinkControllerProvider =
    NotifierProvider<PendingDeepLinkController, PendingDeepLink?>(
      PendingDeepLinkController.new,
    );

