import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Notification types that drive deep-link routing from the notification center.
enum NotificationType {
  /// Generic / system notification — opens the notification detail screen.
  general,

  /// Tied to a specific inventory item — deep-links into inventory.
  inventory,

  /// Tied to a specific order — deep-links into orders (POS / sales).
  order,

  /// Tied to a specific offer — deep-links into offers/pricing.
  offer,

  /// Tied to a subscription / plan — deep-links into account.
  subscription,
}

/// A single notification as returned by the notifications API and rendered in
/// the notification center list.
class NotificationListItem {
  const NotificationListItem({
    required this.id,
    required this.title,
    required this.body,
    required this.read,
    required this.type,
    required this.createdAt,
    this.meta,
    this.extraTitle,
    this.extraId,
  });

  final int id;
  final String title;
  final String body;
  final bool read;
  final NotificationType type;
  final DateTime createdAt;
  final String? meta;
  final String? extraTitle;
  final int? extraId;

  bool get isUnread => !read;
}

/// Full notification detail (same shape as the list item, possibly with more
/// fields from the detail endpoint).
class NotificationDetail extends NotificationListItem {
  const NotificationDetail({
    required super.id,
    required super.title,
    required super.body,
    required super.read,
    required super.type,
    required super.createdAt,
    super.meta,
    super.extraTitle,
    super.extraId,
  });
}

/// Notification preferences as returned by /notification-settings and accepted
/// by the PATCH endpoint.
class NotificationPreferences {
  const NotificationPreferences({
    this.pushEnabled = true,
    this.emailEnabled = true,
    this.smsEnabled = false,
    this.inventoryAlerts = true,
    this.lowStockAlerts = true,
    this.orderAlerts = true,
    this.offerAlerts = true,
    this.promotional = false,
    this.securityAlerts = true,
  });

  final bool pushEnabled;
  final bool emailEnabled;
  final bool smsEnabled;
  final bool inventoryAlerts;
  final bool lowStockAlerts;
  final bool orderAlerts;
  final bool offerAlerts;
  final bool promotional;
  final bool securityAlerts;

  NotificationPreferences copyWith({
    bool? pushEnabled,
    bool? emailEnabled,
    bool? smsEnabled,
    bool? inventoryAlerts,
    bool? lowStockAlerts,
    bool? orderAlerts,
    bool? offerAlerts,
    bool? promotional,
    bool? securityAlerts,
  }) {
    return NotificationPreferences(
      pushEnabled: pushEnabled ?? this.pushEnabled,
      emailEnabled: emailEnabled ?? this.emailEnabled,
      smsEnabled: smsEnabled ?? this.smsEnabled,
      inventoryAlerts: inventoryAlerts ?? this.inventoryAlerts,
      lowStockAlerts: lowStockAlerts ?? this.lowStockAlerts,
      orderAlerts: orderAlerts ?? this.orderAlerts,
      offerAlerts: offerAlerts ?? this.offerAlerts,
      promotional: promotional ?? this.promotional,
      securityAlerts: securityAlerts ?? this.securityAlerts,
    );
  }

  /// JSON form with snake_case keys, so the same payload can be sent to a
  /// future `/shopkeeper/.../notification-settings` endpoint untouched AND be
  /// stored on device (see `NotificationPreferencesStore`).
  Map<String, dynamic> toJson() => <String, dynamic>{
        'push_enabled': pushEnabled,
        'email_enabled': emailEnabled,
        'sms_enabled': smsEnabled,
        'inventory_alerts': inventoryAlerts,
        'low_stock_alerts': lowStockAlerts,
        'order_alerts': orderAlerts,
        'offer_alerts': offerAlerts,
        'promotional': promotional,
        'security_alerts': securityAlerts,
      };

  /// Missing / non-boolean keys fall back to the constructor defaults, so a
  /// partial payload (or an older stored blob) still loads.
  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    bool read(String key, bool fallback) => json[key] as bool? ?? fallback;
    return NotificationPreferences(
      pushEnabled: read('push_enabled', true),
      emailEnabled: read('email_enabled', true),
      smsEnabled: read('sms_enabled', false),
      inventoryAlerts: read('inventory_alerts', true),
      lowStockAlerts: read('low_stock_alerts', true),
      orderAlerts: read('order_alerts', true),
      offerAlerts: read('offer_alerts', true),
      promotional: read('promotional', false),
      securityAlerts: read('security_alerts', true),
    );
  }

  /// Value equality — the preferences screen uses it to decide whether the
  /// current selection differs from what is already saved (unsaved changes).
  @override
  bool operator ==(Object other) =>
      other is NotificationPreferences &&
      other.pushEnabled == pushEnabled &&
      other.emailEnabled == emailEnabled &&
      other.smsEnabled == smsEnabled &&
      other.inventoryAlerts == inventoryAlerts &&
      other.lowStockAlerts == lowStockAlerts &&
      other.orderAlerts == orderAlerts &&
      other.offerAlerts == offerAlerts &&
      other.promotional == promotional &&
      other.securityAlerts == securityAlerts;

  @override
  int get hashCode => Object.hash(
        pushEnabled,
        emailEnabled,
        smsEnabled,
        inventoryAlerts,
        lowStockAlerts,
        orderAlerts,
        offerAlerts,
        promotional,
        securityAlerts,
      );
}

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

/// Compact relative timestamp for one notification row:
/// `just now` → `12m ago` → `3h ago` → `2d ago` → `4 Sep`.
///
/// Lives here (not in a screen) because BOTH notification surfaces render it —
/// the Alerts tab and the Home dashboard strip — and two copies would drift
/// apart the moment one is tweaked.
///
/// [now] is injectable so tests are deterministic instead of depending on the
/// wall clock.
String notificationTimeLabel(DateTime createdAt, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(createdAt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('d MMM').format(createdAt);
}

