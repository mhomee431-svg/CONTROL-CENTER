import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/state/system_state.dart';
import '../../../../core/state/system_state_view.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../domain/notification_models.dart';
import '../controllers/notifications_controller.dart';

/// Shopkeeper notifications — inventory alerts, order activity, subscription
/// and POS sync updates (backend-driven, never fabricated client-side).
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(notificationsControllerProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    // Reload when the shopkeeper switches businesses.
    ref.listen(selectedShopProvider, (prev, next) {
      if (prev?.id != next?.id) {
        ref.read(notificationsControllerProvider.notifier).load();
      }
    });

    final state = ref.watch(notificationsControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (state.status == NotificationsStatus.ready &&
              state.unreadCount > 0)
            TextButton(
              onPressed: () => ref
                  .read(notificationsControllerProvider.notifier)
                  .markAllAsRead(),
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: SafeArea(
        child: switch (state.status) {
          NotificationsStatus.loading =>
            const Center(child: CircularProgressIndicator()),
          NotificationsStatus.error => SystemStateView(
              // The screen owns the retry; the copy, icon and way out come from
              // the shared state vocabulary so this failure reads exactly like
              // every other failure in the app.
              spec: SystemStateSpec.resolve(
                state: SystemState.genericRetry,
                title: state.message ?? 'Could not load notifications.',
                message: 'Check your connection and try again.',
              ),
              onRetry: () =>
                  ref.read(notificationsControllerProvider.notifier).load(),
            ),
          NotificationsStatus.ready => state.items.isEmpty
              ? SystemStateView.empty(
                  title: 'No notifications yet',
                  message: 'Inventory alerts and updates will appear here',
                  icon: Icons.notifications_none,
                )
              : RefreshIndicator(
                  onRefresh: () => ref
                      .read(notificationsControllerProvider.notifier)
                      .load(),
                  child: ListView.separated(
                    itemCount: state.items.length,
                    separatorBuilder: (_, _) => Divider(
                        height: 1, color: Theme.of(context).dividerColor),
                    itemBuilder: (context, index) {
                      final notification = state.items[index];
                      return _NotificationTile(
                        notification: notification,
                        onTap: () => _onTap(notification),
                      );
                    },
                  ),
                ),
        },
      ),
    );
  }

  void _onTap(ShopkeeperNotification notification) {
    // Mark read immediately (optimistic, server-confirmed).
    ref
        .read(notificationsControllerProvider.notifier)
        .markAsRead(notification.id);

    // Deep links follow the shopkeeper section of the app only.
    final link = notification.deepLink;
    if (link != null && link.startsWith('hyperlocal://shopkeeper/')) {
      final target = link.substring('hyperlocal://shopkeeper/'.length);
      if (target.startsWith('inventory')) {
        context.go(Routes.products);
        return;
      }
      if (target.startsWith('dashboard')) {
        context.go(Routes.dashboard);
        return;
      }
    }
    switch (notification.type) {
      case 'INVENTORY_LOW' || 'STOCK_UPDATE' || 'PRICE_UPDATE':
        context.go(Routes.products);
      case 'SHOP_VERIFICATION':
        context.go(Routes.shopProfile);
      case 'SUBSCRIPTION':
        context.go(Routes.account);
      default:
        // Anything else opens its own detail view, so tapping a row is never a
        // dead end.
        context.push(Routes.notificationDetail, extra: notification);
    }
  }
}


class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, this.onTap});

  final ShopkeeperNotification notification;
  final VoidCallback? onTap;

  /// Relative timestamp — rendered through the SHARED helper so the Alerts
  /// tab and the Home dashboard strip always read identically.
  String get _timeLabel => notificationTimeLabel(notification.createdAt);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unread = notification.isUnread;

    return ListTile(
      onTap: onTap,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Badge(
        isLabelVisible: unread,
        smallSize: 10,
        child: CircleAvatar(
          backgroundColor: unread
              ? scheme.primaryContainer
              : theme.dividerColor.withValues(alpha: 0.3),
          child: Icon(
            notificationIcon(notification.type),
            size: 20,
            color: unread ? scheme.primary : scheme.outline,
          ),
        ),
      ),
      title: Text(
        notification.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        notification.body,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          color: unread ? scheme.onSurface : scheme.outline,
        ),
      ),
      trailing: Text(
        _timeLabel,
        style: TextStyle(fontSize: 11, color: scheme.outline),
      ),
    );
  }
}


