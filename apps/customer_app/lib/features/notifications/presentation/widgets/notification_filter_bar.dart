import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/models/app_notification.dart';

/// Customer Alerts filter groups.
///
/// Mirrors the notification categories named in the product spec (§47):
/// Price Drops · Offers · Availability Updates · Shop Updates · System
/// Messages. Each filter claims the [NotificationType]s that belong to it, so
/// grouping is derived from the existing taxonomy and never invents a new one.
///
/// [all] claims nothing (`types == null`) and therefore matches every row — a
/// type added to [NotificationType] later still shows up under "All" until a
/// dedicated filter claims it.
enum NotificationFilter {
  all('All', Icons.all_inbox_outlined, null),
  priceDrops('Price Drops', Icons.sell_outlined, {NotificationType.priceDrop}),
  offers('Offers', Icons.campaign_outlined, {NotificationType.offer}),
  availability('Availability', Icons.inventory_2_outlined,
      {NotificationType.productAvailable}),
  shopUpdates('Shop Updates', Icons.storefront_outlined,
      {NotificationType.shopUpdate}),
  orders('Orders', Icons.local_shipping_outlined,
      {NotificationType.orderUpdate}),
  system('System', Icons.notifications_outlined, {NotificationType.system});

  const NotificationFilter(this.label, this.icon, this.types);

  /// Human-readable chip label.
  final String label;

  /// Chip icon (row icons come from `iconForNotificationType`).
  final IconData icon;

  /// Types claimed by this filter; null for [all], which matches everything.
  final Set<NotificationType>? types;

  /// True when [notification] belongs to the selected filter.
  bool matches(AppNotification notification) =>
      types == null || types!.contains(notification.type);
}

/// Horizontal category filter for the customer Alerts list.
///
/// "All" plus one chip per [NotificationFilter]. Every chip is always listed —
/// even when it currently has no rows — so the bar does not shift around as
/// notifications arrive.
class NotificationFilterBar extends StatelessWidget {
  const NotificationFilterBar({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final NotificationFilter selected;
  final ValueChanged<NotificationFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        children: [
          for (final filter in NotificationFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: FilterChip(
                key: Key('notification-filter-${filter.name}'),
                selected: selected == filter,
                onSelected: (_) => onSelect(filter),
                avatar: Icon(filter.icon, size: 16),
                label: Text(filter.label),
              ),
            ),
        ],
      ),
    );
  }
}