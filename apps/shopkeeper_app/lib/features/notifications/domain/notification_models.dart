import 'package:flutter/material.dart';

/// Domain models for the Shopkeeper notifications feature.
///
/// Maps to the backend `GET /shopkeeper/shops/{id}/notifications` response
/// (shopkeeper_extra.py). Notifications are user-scoped rows surfaced to
/// every owner/manager of the shop.

/// One notification row as delivered to a shopkeeper.
class ShopkeeperNotification {
  const ShopkeeperNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    required this.createdAt,
    this.deepLink,
  });

  final int id;
  final String title;
  final String body;

  /// Raw backend type, e.g. `INVENTORY_LOW`, `ORDER`, `SUBSCRIPTION`,
  /// `POS_SYNC`, `SHOP_VERIFICATION`.
  final String type;
  final bool isRead;
  final DateTime createdAt;

  /// Optional in-app deep link, e.g. `hyperlocal://shopkeeper/inventory/42`.
  final String? deepLink;

  bool get isUnread => !isRead;

  factory ShopkeeperNotification.fromJson(Map<String, dynamic> json) =>
      ShopkeeperNotification(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        type: json['type'] as String? ?? 'GENERAL',
        isRead: json['is_read'] as bool? ?? false,
        createdAt: _parseDate(json['created_at']),
        deepLink: json['deep_link'] as String?,
      );

  static DateTime _parseDate(Object? raw) {
    if (raw is DateTime) return raw;
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw) ?? DateTime.now();
    }
    return DateTime.now();
  }
}

/// Full notifications page payload.
class NotificationsPage {
  const NotificationsPage({
    required this.items,
    required this.unreadCount,
  });

  final List<ShopkeeperNotification> items;
  final int unreadCount;

  bool get isEmpty => items.isEmpty;

  factory NotificationsPage.fromJson(Map<String, dynamic> json) =>
      NotificationsPage(
        items: ((json['notifications'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ShopkeeperNotification.fromJson)
            .toList(growable: false),
        unreadCount: (json['unread'] as num?)?.toInt() ?? 0,
      );
}

/// Material icon for a backend notification type.
IconData notificationIcon(String type) => switch (type) {
      'INVENTORY_LOW' || 'STOCK_UPDATE' => Icons.inventory_2_outlined,
      'ORDER' || 'ORDER_NEW' => Icons.shopping_bag_outlined,
      'SUBSCRIPTION' => Icons.card_membership_outlined,
      'POS_SYNC' => Icons.sync_outlined,
      'SHOP_VERIFICATION' => Icons.verified_user_outlined,
      'PRICE_UPDATE' => Icons.price_change_outlined,
      _ => Icons.notifications_outlined,
    };

