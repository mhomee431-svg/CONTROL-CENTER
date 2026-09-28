import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/app_notification.dart';
import '../../domain/models/notification_preferences.dart';

/// How a notification that arrives while the app is ALREADY OPEN should be
/// surfaced in-app.
///
/// Foreground delivery is the most delicate of the three FCM paths: the
/// customer is looking at the app right now, so anything modal is an
/// interruption. The presentation is therefore graded by how time-sensitive
/// the message is, never by "always show a dialog".
enum InAppPresentation {
  /// Non-blocking card pinned to the top of the screen. Auto-dismisses.
  /// Used for informational alerts the customer can safely read later.
  banner,

  /// Lightweight transient message. Auto-dismisses. Used for low-priority
  /// commercial messages that must not occupy screen space.
  snackBar,

  /// Modal acknowledgement, shown only for transactional messages the
  /// customer is waiting on. Still auto-releases when it is dismissed.
  dialog,

  /// Not shown in-app at all. The customer's own settings turned it off.
  silent,
}

/// Grading policy for foreground delivery.
///
/// Pure function (no BuildContext, no Riverpod) so the whole matrix is unit
/// testable — the rules are the product decision, and they must not drift.
///
/// Two independent gates are honoured:
///  1. the device-wide master switch ([AppSettings.pushNotificationsEnabled]),
///     which also drives device-token registration; and
///  2. the account-level per-type opt-outs ([NotificationPreferences]).
///
/// Only after both gates does the message get an [InAppPresentation] tier.
InAppPresentation decideInAppPresentation({
  required NotificationType type,
  required bool pushEnabled,
  required NotificationPreferences preferences,
}) {
  // Gate 1 — the customer switched push off for this device entirely.
  if (!pushEnabled) return InAppPresentation.silent;
  // Gate 2 — the account-level master switch (mirrors the API's push_enabled).
  if (!preferences.pushEnabled) return InAppPresentation.silent;

  // Per-type opt-outs, mirroring the backend decision table
  // (`notification_service._TYPE_REGISTRY`), which gates exactly these three
  // customer-facing types. Anything the backend does not gate cannot be
  // opted out of here either — otherwise the app would suppress a message
  // the backend still sends.
  switch (type) {
    case NotificationType.priceDrop:
      if (!preferences.priceAlerts) return InAppPresentation.silent;
      return InAppPresentation.banner;
    case NotificationType.productAvailable:
      if (!preferences.availabilityAlerts) return InAppPresentation.silent;
      return InAppPresentation.banner;
    case NotificationType.offer:
      if (!preferences.promotional && !preferences.dealAlerts) {
        return InAppPresentation.silent;
      }
      return InAppPresentation.snackBar;
    // The backend has no `shop_updates` gate, so a shop update is shown
    // whenever push is on. Once the backend adds a column, this becomes a
    // `preferences.shopUpdates` check — the change is one line, made here
    // where the policy lives, rather than silently diverging in two places.
    case NotificationType.shopUpdate:
      return InAppPresentation.banner;
    // Transactional (order) and service (system) messages are never gated by
    // the backend and always surface once push is enabled.
    case NotificationType.orderUpdate:
      return InAppPresentation.dialog;
    case NotificationType.system:
      return InAppPresentation.snackBar;
  }
}

/// A queued in-app message together with the tier it was granted.
@immutable
class InAppNotificationItem {
  final AppNotification notification;
  final InAppPresentation presentation;

  const InAppNotificationItem(this.notification, this.presentation);

  @override
  bool operator ==(Object other) =>
      other is InAppNotificationItem &&
      other.notification == notification &&
      other.presentation == presentation;

  @override
  int get hashCode => Object.hash(notification, presentation);
}

/// In-app presentation state: at most one [active] message is on screen, the
/// rest wait in [queue] and are promoted one at a time.
@immutable
class InAppNotificationState {
  /// Messages waiting behind the active one.
  final List<InAppNotificationItem> queue;

  /// The message currently on screen, if any.
  final InAppNotificationItem? active;

  const InAppNotificationState({this.queue = const [], this.active});

  bool get isIdle => active == null;
}

/// Owns the foreground (in-app) notification queue.
///
/// Deliberately separate from `NotificationsController`: that one is the
/// persisted inbox fetched from the API, while this is the transient
/// "something just arrived" surface. Keeping them apart means a failed
/// inbox fetch can never swallow a live push, and vice versa.
class InAppNotificationController extends Notifier<InAppNotificationState> {
  /// Upper bound on *waiting* messages. A burst of pushes must never build
  /// an unbounded backlog the customer would then have to dismiss one by
  /// one — the oldest waiting items are dropped instead.
  ///
  /// Static because it is a constant of the policy, not per-instance state.
  static const int maxQueueLength = 3;

  @override
  InAppNotificationState build() => const InAppNotificationState();

  /// Queues [notification] at [presentation] and returns whether it was
  /// accepted. A [InAppPresentation.silent] tier is always rejected, so
  /// callers can pass a freshly graded message without pre-checking.
  ///
  /// Idempotent by id: the same push can legitimately arrive twice (the
  /// foreground stream plus a concurrent inbox refresh), and the customer
  /// must not see it twice.
  bool enqueue(
    AppNotification notification, {
    required InAppPresentation presentation,
  }) {
    if (presentation == InAppPresentation.silent) return false;
    final current = state;
    final item = InAppNotificationItem(notification, presentation);

    final alreadyShown =
        (current.active?.notification.id.isNotEmpty ?? false) &&
        current.active!.notification.id == notification.id;
    final alreadyQueued = current.queue.any(
      (queued) =>
          queued.notification.id.isNotEmpty &&
          queued.notification.id == notification.id,
    );
    if (alreadyShown || alreadyQueued) return false;

    // First message goes straight on screen; the rest line up behind it.
    if (current.active == null) {
      state = InAppNotificationState(active: item);
      return true;
    }

    final next = [...current.queue, item];
    state = InAppNotificationState(
      queue: next.length > maxQueueLength
          ? next.sublist(next.length - maxQueueLength)
          : next,
      active: current.active,
    );
    return true;
  }

  /// Clears the active message and promotes the next queued one (if any).
  void dismissActive() {
    final current = state;
    if (current.active == null) return;
    if (current.queue.isEmpty) {
      state = const InAppNotificationState();
      return;
    }
    state = InAppNotificationState(
      active: current.queue.first,
      queue: current.queue.sublist(1),
    );
  }

  /// Drops everything — used on logout so one account's alerts can never
  /// surface in another account's session.
  void clear() => state = const InAppNotificationState();
}

final inAppNotificationControllerProvider =
    NotifierProvider<InAppNotificationController, InAppNotificationState>(
      InAppNotificationController.new,
    );

