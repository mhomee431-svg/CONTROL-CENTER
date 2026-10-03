import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/empty_state_view.dart';
import '../../../../core/widgets/list_loading_view.dart';
import '../../domain/models/app_notification.dart';
import '../controllers/deep_link_handler.dart';
import '../controllers/notifications_controller.dart';
import '../widgets/notification_filter_bar.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// Active category filter; [NotificationFilter.all] means "no filter".
  ///
  /// Kept in the screen (not the controller) because it is pure view state —
  /// the loaded list stays the same, only the visible slice changes. Filtering
  /// client-side keeps switching instant and never refetches.
  NotificationFilter _filter = NotificationFilter.all;

  /// Clears the active filter — the "Show all notifications" action on the
  /// filtered-empty state.
  ///
  /// Guarded on already being `all` so tapping it never triggers a pointless
  /// rebuild of the list.
  void _clearFilter() {
    if (_filter == NotificationFilter.all) return;
    setState(() => _filter = NotificationFilter.all);
  }

  @override
  Widget build(BuildContext context) {
    final notificationsAsync = ref.watch(notificationsControllerProvider);
    final unreadCount = ref.watch(unreadCountProvider);
    final tapHandler = ref.read(notificationTapHandlerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Alerts'),
            if (unreadCount > 0) ...[
              const SizedBox(width: AppSpacing.sm),
              Badge(
                label: Text('$unreadCount'),
                backgroundColor: AppColors.primary,
                child: const Icon(Icons.notifications_none, size: 20),
              ),
            ],
          ],
        ),
        actions: [
          if (unreadCount > 0)
            TextButton(
              key: const Key('markAllReadButton'),
              onPressed: () => ref
                  .read(notificationsControllerProvider.notifier)
                  .markAllAsRead(),
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: notificationsAsync.when(
        loading: () => ListLoadingView(
          message: 'Loading your notifications…',
          onRetry: () =>
              ref.read(notificationsControllerProvider.notifier).refresh(),
        ),
        error: (error, _) => _ErrorStateView(
          onRetry: () =>
              ref.read(notificationsControllerProvider.notifier).refresh(),
        ),
        data: (notifications) {
          if (notifications.isEmpty) {
            return const EmptyNotificationsView();
          }
          final visible = notifications
              .where(_filter.matches)
              .toList(growable: false);
          return Column(
            children: [
              NotificationFilterBar(
                selected: _filter,
                onSelect: (filter) => setState(() => _filter = filter),
              ),
              const Divider(height: 1),
              Expanded(
                child: visible.isEmpty
                    ? _FilteredEmptyView(
                        filter: _filter,
                        onClearFilter: _clearFilter,
                      )
                    : RefreshIndicator(
                        onRefresh: () => ref
                            .read(notificationsControllerProvider.notifier)
                            .refresh(),
                        child: ListView.separated(
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = visible[index];
                            return _NotificationTile(
                              notification: item,
                              onTap: () => tapHandler.handleTap(context, item),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationTile({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isUnread = !notification.isRead;
    return ListTile(
      key: Key('notification_${notification.id}'),
      onTap: onTap,
      tileColor: isUnread ? AppColors.primary.withValues(alpha: 0.05) : null,
      leading: CircleAvatar(
        backgroundColor: isUnread
            ? AppColors.primary.withValues(alpha: 0.15)
            : Colors.grey.shade200,
        child: Icon(
          iconForNotificationType(notification.type),
          color: isUnread ? AppColors.primary : Colors.grey,
          size: 20,
        ),
      ),
      title: Text(
        notification.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        notification.body,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatNotificationTimestamp(notification.timestamp),
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          if (isUnread) ...[
            const SizedBox(width: AppSpacing.sm),
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The inbox is genuinely empty (as opposed to filtered to nothing).
///
/// Carries a next action: an empty inbox is otherwise a dead end, and the useful
/// thing to do is go find something worth being notified about.
class EmptyNotificationsView extends StatelessWidget {
  const EmptyNotificationsView({super.key});

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      icon: Icons.notifications_off_outlined,
      title: 'No notifications yet',
      message: 'We will notify you about price drops, offers and shop updates.',
      actionLabel: 'Explore shops',
      actionIcon: Icons.search,
      onActionTap: () => context.push('/search'),
    );
  }
}

/// Shown when the list has rows but none belong to the selected filter.
///
/// The copy names the active filter so the empty screen explains itself, and the
/// action removes that filter — the customer's real problem here is a filter they
/// set, not a lack of notifications, so "clear the filter" is the useful next step.
class _FilteredEmptyView extends StatelessWidget {
  const _FilteredEmptyView({required this.filter, this.onClearFilter});

  final NotificationFilter filter;
  final VoidCallback? onClearFilter;

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      icon: filter.icon,
      title: 'No ${filter.label} notifications',
      message: 'New ${filter.label.toLowerCase()} updates will appear here.',
      actionLabel: 'Show all notifications',
      actionIcon: Icons.filter_alt_off_outlined,
      onActionTap: onClearFilter,
    );
  }
}

class _ErrorStateView extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorStateView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 64,
              color: AppColors.error,
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Couldn\'t load notifications',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Something went wrong. Please check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton.icon(
              key: const Key('notificationsRetryButton'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
