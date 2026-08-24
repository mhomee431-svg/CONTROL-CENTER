import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/app_notification.dart';
import 'notifications_controller.dart';

/// Outcome of resolving a notification's deep link.
enum DeepLinkAction {
  /// Navigate to [path].
  navigate,

  /// The link exists but its content can't be opened (expired offer,
  /// destination not shipped yet, …) — show a friendly fallback.
  unavailable,

  /// Nothing to navigate to; tapping just marks the item read.
  none,
}

class DeepLinkResolution {
  final DeepLinkAction action;

  /// App route path when [action] is [DeepLinkAction.navigate].
  final String? path;

  /// User-facing explanation when [action] is [DeepLinkAction.unavailable].
  final String? message;

  const DeepLinkResolution._(this.action, this.path, this.message);

  const DeepLinkResolution.navigate(String path)
      : this._(DeepLinkAction.navigate, path, null);

  const DeepLinkResolution.unavailable(String message)
      : this._(DeepLinkAction.unavailable, null, message);

  static const DeepLinkResolution none =
      DeepLinkResolution._(DeepLinkAction.none, null, null);
}

/// Pure mapping from a notification to a navigation outcome.
///
/// Kept free of BuildContext so it is fully unit-testable. Unknown or
/// expired targets never produce a route — they degrade to
/// [DeepLinkAction.unavailable] so the UI can respond safely.
DeepLinkResolution resolveNotificationDeepLink(AppNotification notification) {
  final link = notification.deepLink;
  if (link.targetType == DeepLinkTargetType.none) {
    return DeepLinkResolution.none;
  }
  if (!link.isValid()) {
    // Covers malformed ids and expired links alike.
    return const DeepLinkResolution.unavailable(
      'This content is no longer available.',
    );
  }
  switch (link.targetType) {
    case DeepLinkTargetType.product:
      return DeepLinkResolution.navigate('/product/${link.targetId}');
    case DeepLinkTargetType.shop:
      return DeepLinkResolution.navigate('/shop/${link.targetId}');
    case DeepLinkTargetType.offer:
      // No offer detail screen exists yet — never crash, explain instead.
      return const DeepLinkResolution.unavailable(
        'Offers are coming soon. This one can\'t be opened yet.',
      );
    case DeepLinkTargetType.none:
      return DeepLinkResolution.none;
  }
}

/// Turns notification taps into navigation while keeping all delivery /
/// routing policy out of the widget tree.
class NotificationTapHandler {
  final Ref _ref;

  NotificationTapHandler(this._ref);

  /// Marks the notification read and navigates when the link is usable.
  ///
  /// Navigation failures (unknown route at runtime, disposed context…)
  /// are caught and surface the safe fallback message.
  Future<void> handleTap(
    BuildContext context,
    AppNotification notification,
  ) async {
    await _ref.read(notificationsControllerProvider.notifier).markAsRead(
          notification.id,
        );

    final resolution = resolveNotificationDeepLink(notification);
    switch (resolution.action) {
      case DeepLinkAction.none:
        break;
      case DeepLinkAction.navigate:
        try {
          if (!context.mounted) return;
          await GoRouter.of(context).push(resolution.path!);
        } catch (_) {
          if (context.mounted) _showUnavailable(context, resolution.message);
        }
        break;
      case DeepLinkAction.unavailable:
        if (context.mounted) _showUnavailable(context, resolution.message);
        break;
    }
  }

  void _showUnavailable(BuildContext context, String? message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message ?? 'This content is no longer available.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

final notificationTapHandlerProvider = Provider<NotificationTapHandler>(
  (ref) => NotificationTapHandler(ref),
);

/// Icon for each notification type (presentation-only concern).
IconData iconForNotificationType(NotificationType type) {
  switch (type) {
    case NotificationType.priceDrop:
      return Icons.sell_outlined;
    case NotificationType.productAvailable:
      return Icons.inventory_2_outlined;
    case NotificationType.offer:
      return Icons.campaign_outlined;
    case NotificationType.shopUpdate:
      return Icons.storefront_outlined;
    case NotificationType.orderUpdate:
      return Icons.local_shipping_outlined;
    case NotificationType.system:
      return Icons.notifications_outlined;
  }
}

/// Compact human timestamp for list rows ("now", "5m", "3h", "2d").
String formatNotificationTimestamp(DateTime timestamp, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final difference = reference.difference(timestamp);
  if (difference.inMinutes < 1) return 'now';
  if (difference.inHours < 1) return '${difference.inMinutes}m';
  if (difference.inDays < 1) return '${difference.inHours}h';
  if (difference.inDays < 7) return '${difference.inDays}d';
  return '${timestamp.day}/${timestamp.month}';
}
