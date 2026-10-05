import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/state/system_state.dart';
import '../../../../core/state/system_state_view.dart';
import '../../../../core/ui/lazy_list.dart';
import '../../../../core/ui/load_more.dart';
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
  /// Active category filter; `null` means "All".
  ///
  /// Kept in the screen (not the controller) because it is pure view state —
  /// the loaded page stays the same, only the visible slice changes.
  NotificationCategory? _categoryFilter;

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
        title: Text(appText(context).commonNotifications2),
        actions: [
          if (state.status == NotificationsStatus.ready &&
              state.unreadCount > 0)
            TextButton(
              onPressed: () => ref
                  .read(notificationsControllerProvider.notifier)
                  .markAllAsRead(),
              child: Text(appText(context).commonMarkAllRead),
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
                text: appText(context),
                state: SystemState.genericRetry,
                title: state.message ?? 'Could not load notifications.',
                message: appText(context).notificationsScreenCheckYourConnectionAndTry,
              ),
              onRetry: () =>
                  ref.read(notificationsControllerProvider.notifier).load(),
            ),
          NotificationsStatus.ready => _readyBody(state),
        },
      ),
    );
  }

  /// Ready body: category filter bar above the (filtered) list.
  ///
  /// Filtering is client-side over the already-loaded pages, so switching
  /// category is instant and never refetches. Paging, by contrast, IS a
  /// backend call: the rows arrive a page at a time ([NotificationsState.total]
  /// comes from the server), and the footer reveals the next page — the same
  /// `LoadMoreTile` the catalog lists use, so a paged list behaves identically
  /// everywhere in the app.
  Widget _readyBody(NotificationsState state) {
    final theme = Theme.of(context);
    final filter = _categoryFilter;
    final visible = filter == null
        ? state.items
        : state.items
            .where((n) => filter.matches(n.type))
            .toList(growable: false);

    return Column(
      children: [
        _CategoryFilterBar(
          selected: filter,
          onSelect: (category) => setState(() => _categoryFilter = category),
        ),
        Divider(height: 1, color: theme.dividerColor),
        Expanded(
          child: visible.isEmpty && !state.hasMore
              ? SystemStateView.empty(
                  title: filter == null
                      ? 'No notifications yet'
                      : 'No ${filter.label} notifications',
                  message: filter == null
                      ? 'Inventory alerts and updates will appear here'
                      : 'New ${filter.label.toLowerCase()} updates will '
                          'appear here',
                  icon: filter?.icon ?? Icons.notifications_none,
                )
              : RefreshIndicator(
                  onRefresh: () => ref
                      .read(notificationsControllerProvider.notifier)
                      .load(),
                  child: LazyListView(
                    // Always scrollable: pull works on a short (or empty)
                    // notification list.
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: visible.length,
                    padding: EdgeInsets.zero,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: theme.dividerColor),
                    itemBuilder: (context, index) {
                      final notification = visible[index];
                      return _NotificationTile(
                        notification: notification,
                        onTap: () => _onTap(notification),
                      );
                    },
                    // A filter that hid every loaded row still leaves rows on
                    // the server: "Load more" stays reachable (the loaded pages
                    // are filtered client-side), and the empty state is only
                    // shown once the server has nothing left to send.
                    emptyPlaceholder: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          filter == null
                              ? 'No notifications on this page.'
                              : 'No ${filter.label} notifications on this page.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.outline),
                        ),
                      ),
                    ),
                    footer: [
                      if (state.hasMore)
                        LoadMoreTile(
                          key: const Key('notifications-load-more'),
                          hidden: state.hidden,
                          onTap: state.loadingMore
                              ? () {}
                              : () => ref
                                  .read(notificationsControllerProvider.notifier)
                                  .loadMore(),
                        ),
                      if (state.loadingMore)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                      // A page that failed keeps the rows already loaded and
                      // says why — it never blanks the list.
                      if (state.message != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          child: Text(
                            state.message!,
                            key: const Key('notifications-page-error'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  void _onTap(ShopkeeperNotification notification) {
    // Mark read immediately (optimistic, server-confirmed).
    ref
        .read(notificationsControllerProvider.notifier)
        .markAsRead(notification.id);

    // Where to go is a single, unit-tested decision (notificationRouteTarget):
    // deep-link section or type, refined by the validated payload — never a
    // bare id, because the item screens need a whole object, not an id.
    final target = notificationRouteTarget(notification);
    if (target == Routes.notificationDetail) {
      context.push(target, extra: notification);
      return;
    }
    if (target == Routes.importResult) {
      // The id was already validated by `payloadInt` on the way to the target
      // decision; pass the SAME validated value so the screen and the route
      // agree, and a payload that changed shape between the two reads cannot
      // send them to different jobs.
      final jobId = notification.payloadInt('job_id');
      if (jobId == null) {
        // Unreachable via notificationRouteTarget, but a screen that can no
        // longer be opened must not crash the tap.
        context.go(Routes.importHistory);
        return;
      }
      context.push(target, extra: jobId);
      return;
    }
    if (kNotificationTabTargets.contains(target)) {
      context.go(target);
    } else {
      context.push(target);
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


/// Horizontal category filter for the Alerts tab.
///
/// "All" plus one chip per [NotificationCategory]. Every category is always
/// listed — even when it currently has no rows — so the bar does not shift
/// around as notifications arrive.
class _CategoryFilterBar extends StatelessWidget {
  const _CategoryFilterBar({required this.selected, required this.onSelect});

  final NotificationCategory? selected;
  final ValueChanged<NotificationCategory?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        children: [
          _CategoryChip(
            key: const Key('notification-filter-all'),
            label: appText(context).commonAll2,
            icon: Icons.all_inbox_outlined,
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final category in NotificationCategory.values)
            _CategoryChip(
              key: Key('notification-filter-${category.name}'),
              label: category.label,
              icon: category.icon,
              selected: selected == category,
              onTap: () => onSelect(category),
            ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: selected,
        onSelected: (_) => onTap(),
        avatar: Icon(icon, size: 16),
        label: Text(label),
      ),
    );
  }
}
