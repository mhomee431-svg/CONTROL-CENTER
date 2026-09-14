import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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
    final scheme = Theme.of(context).colorScheme;

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
          NotificationsStatus.error => _ErrorView(
              message: state.message ?? 'Could not load notifications.',
              onRetry: () =>
                  ref.read(notificationsControllerProvider.notifier).load(),
            ),
          NotificationsStatus.ready => state.items.isEmpty
              ? _EmptyView(color: scheme.outline)
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
        context.go('/products');
        return;
      }
      if (target.startsWith('dashboard')) {
        context.go('/dashboard');
        return;
      }
    }
    switch (notification.type) {
      case 'INVENTORY_LOW' || 'STOCK_UPDATE' || 'PRICE_UPDATE':
        context.go('/products');
      case 'SHOP_VERIFICATION':
        context.go('/shop-profile');
      case 'SUBSCRIPTION':
        context.go('/account');
    }
  }
}


class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, this.onTap});

  final ShopkeeperNotification notification;
  final VoidCallback? onTap;

  String get _timeLabel {
    final n = notification.createdAt;
    final diff = DateTime.now().difference(n);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('d MMM').format(n);
  }

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

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none, size: 64, color: color),
          const SizedBox(height: 16),
          Text('No notifications yet',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Inventory alerts and updates will appear here',
            style: TextStyle(
                fontSize: 13, color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
