import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../controllers/deep_link_handler.dart';
import '../controllers/in_app_notification_controller.dart';
import '../controllers/pending_deep_link_controller.dart';
import '../controllers/notifications_controller.dart';

/// How long a non-modal in-app message stays on screen before it releases
/// itself. Long enough to read a price drop, short enough that it never
/// becomes clutter the customer has to dismiss by hand.
const Duration inAppBannerDuration = Duration(seconds: 5);

/// Renders the single active foreground notification above whatever screen
/// the customer happens to be on.
///
/// Mounted once from `MaterialApp.builder`, which is what makes foreground
/// delivery work on *every* screen without each screen knowing that push
/// exists. A push can land on the map, the search results, a half-typed
/// search box — none of which should have to opt in.
///
/// UX rules encoded here:
///  * **Never steals focus or navigation.** Tapping opens the target; simply
///    receiving a message changes nothing about where the customer is.
///  * **Never blocks.** The banner floats above content and auto-releases.
///  * **Degrades to nothing.** No resolvable deep link means the banner
///    still informs, but does not pretend to be tappable.
class InAppNotificationHost extends ConsumerStatefulWidget {
  const InAppNotificationHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<InAppNotificationHost> createState() =>
      _InAppNotificationHostState();
}

class _InAppNotificationHostState extends ConsumerState<InAppNotificationHost> {
  Timer? _autoRelease;

  /// Id of the dialog-tier message already on screen, so a rebuild (theme
  /// change, provider tick, rotation) does not stack a second dialog on top
  /// of the first.
  String? _dialogShowingFor;

  @override
  void dispose() {
    _autoRelease?.cancel();
    super.dispose();
  }

  void _scheduleAutoRelease(InAppNotificationItem? item) {
    _autoRelease?.cancel();
    // Modal tiers own their own dismissal — never auto-close a dialog the
    // customer is still reading.
    if (item == null || item.presentation == InAppPresentation.dialog) return;
    _autoRelease = Timer(inAppBannerDuration, () {
      if (!mounted) return;
      ref.read(inAppNotificationControllerProvider.notifier).dismissActive();
    });
  }

  Future<void> _open(InAppNotificationItem item) async {
    final controller = ref.read(inAppNotificationControllerProvider.notifier);
    controller.dismissActive();

    final notification = item.notification;
    if (notification.id.isNotEmpty) {
      // Optimistic + best-effort: never block the tap on the network.
      unawaited(
        ref
            .read(notificationsControllerProvider.notifier)
            .markAsRead(notification.id),
      );
    }

    final resolution = resolveNotificationDeepLink(notification);
    switch (resolution.action) {
      case DeepLinkAction.navigate:
        // Queue rather than navigate inline. The app is already past its
        // launch gates here, so the drain provider fires on the next frame —
        // but keeping every entry point on the same code path is what
        // guarantees consistent behaviour across all three FCM states.
        await ref
            .read(pendingDeepLinkControllerProvider.notifier)
            .enqueue(resolution.path!, notificationId: notification.id);
      case DeepLinkAction.unavailable:
        if (mounted) showInAppMessage(context, resolution.message);
      case DeepLinkAction.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inAppNotificationControllerProvider);
    final active = state.active;
    _scheduleAutoRelease(active);

    // `dialog` is the only modal tier, and it is raised for transactional
    // messages only (see `decideInAppPresentation`).
    if (active != null &&
        active.presentation == InAppPresentation.dialog &&
        _dialogShowingFor != active.notification.id) {
      _dialogShowingFor = active.notification.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_presentDialog(active));
      });
    }

    return Stack(
      children: [
        widget.child,
        if (active != null && active.presentation != InAppPresentation.dialog)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: _InAppSurface(
                item: active,
                onTap: () => _open(active),
                onDismiss: () => ref
                    .read(inAppNotificationControllerProvider.notifier)
                    .dismissActive(),
              ),
            ),
          ),
      ],
    );
  }

  /// Raises the modal tier.
  ///
  /// Named `_presentDialog` rather than `showDialog` on purpose: a method
  /// called `showDialog` shadows Flutter's top-level `showDialog<String>` used
  /// a few lines below, which is exactly the kind of self-inflicted breakage
  /// that only shows up as a baffling type error.
  Future<void> _presentDialog(InAppNotificationItem item) async {
    final notification = item.notification;
    final resolution = resolveNotificationDeepLink(notification);
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('inAppNotificationDialog'),
        icon: Icon(iconForNotificationType(notification.type)),
        title: Text(notification.title),
        content: Text(notification.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Dismiss'),
          ),
          if (resolution.action == DeepLinkAction.navigate)
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(resolution.path),
              child: const Text('View'),
            ),
        ],
      ),
    );
    if (!mounted) return;
    ref.read(inAppNotificationControllerProvider.notifier).dismissActive();
    if (action != null) {
      await ref
          .read(pendingDeepLinkControllerProvider.notifier)
          .enqueue(action, notificationId: notification.id);
    }
  }
}

/// The visual card for a foreground message.
class _InAppSurface extends StatelessWidget {
  const _InAppSurface({
    required this.item,
    required this.onTap,
    required this.onDismiss,
  });

  final InAppNotificationItem item;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notification = item.notification;
    // The snackBar tier is a single line: the customer should be able to
    // glance at it and keep going.
    final isCompact = item.presentation == InAppPresentation.snackBar;

    final card = Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.surface,
      child: InkWell(
        key: Key('inAppNotification_${notification.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + AppSpacing.xs,
          ),
          child: Row(
            children: [
              Icon(
                iconForNotificationType(notification.type),
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      notification.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    if (!isCompact)
                      Text(
                        notification.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('inAppNotificationDismiss'),
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Dismiss',
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Align(alignment: Alignment.topCenter, child: card),
    );
  }
}
