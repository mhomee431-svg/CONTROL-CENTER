import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/router/route_names.dart';

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
    this.payload,
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

  /// Structured backend payload, e.g. `{"event": "PROFILE_UPDATED"}` or
  /// `{"shop_product_id": 42, "status": "PARTIAL"}`.
  ///
  /// Only ever read through the validated accessors below — a malformed
  /// payload must never steer navigation.
  final Map<String, dynamic>? payload;

  bool get isUnread => !isRead;

  /// `event` from [payload], validated: only a non-empty string counts.
  /// Anything else (missing, wrong type, blank) is treated as absent.
  String? get payloadEvent {
    final raw = payload?['event'];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    return null;
  }

  /// An integer id from [payload], validated before any navigation could use
  /// it: it must be an int (or a whole number) and strictly positive.
  /// Returns null for anything else, so a malformed payload can never send
  /// the shopkeeper to a fabricated item.
  int? payloadInt(String key) {
    final raw = payload?[key];
    if (raw is int && raw > 0) return raw;
    if (raw is num && raw > 0 && raw == raw.round()) return raw.round();
    return null;
  }

  factory ShopkeeperNotification.fromJson(Map<String, dynamic> json) =>
      ShopkeeperNotification(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        type: json['type'] as String? ?? 'GENERAL',
        isRead: json['is_read'] as bool? ?? false,
        createdAt: _parseDate(json['created_at']),
        deepLink: json['deep_link'] as String?,
        payload: _parsePayload(json['payload']),
      );

  /// Accepts an object as-is or a JSON-encoded string; anything else (or an
  /// undecodable string) becomes null instead of throwing.
  static Map<String, dynamic>? _parsePayload(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static DateTime _parseDate(Object? raw) {
    if (raw is DateTime) return raw;
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw) ?? DateTime.now();
    }
    return DateTime.now();
  }
}

/// How many rows one notifications request asks for.
///
/// The shop-notifications endpoint accepts `limit` 1…100; 20 is its own default
/// and the page size the list was designed around, so the first request matches
/// the server's own framing and each "Load more" is one bounded round trip
/// instead of a full history dump.
const int notificationsPageSize = 20;

/// One page of the notifications endpoint, plus the counters the screen needs.
class NotificationsPage {
  const NotificationsPage({
    required this.items,
    required this.unreadCount,
    this.total = 0,
  });

  final List<ShopkeeperNotification> items;
  final int unreadCount;

  /// How many notifications THIS shop has in total, as counted by the server
  /// across every page (not just the rows in this response).
  ///
  /// It exists so "is there another page?" is answered by the backend rather
  /// than guessed from a short page — a page that ends exactly on a size
  /// boundary would otherwise look like the end of the list.
  final int total;

  bool get isEmpty => items.isEmpty;

  /// True when this response did not carry every row the server holds.
  bool get hasMore => items.length < total;

  factory NotificationsPage.fromJson(Map<String, dynamic> json) {
    final items = ((json['notifications'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ShopkeeperNotification.fromJson)
        .toList(growable: false);
    // Older payloads omit `total`; falling back to the row count keeps
    // `hasMore` false (no invented "load more") instead of promising a page
    // the server never said existed.
    return NotificationsPage(
      items: items,
      unreadCount: (json['unread'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? items.length,
    );
  }
}

/// Material icon for a backend notification type.
///
/// The type is a raw server string — new backend types fall through to a
/// neutral bell instead of throwing, so an unknown category still renders.
IconData notificationIcon(String type) => switch (type.toUpperCase()) {
      'INVENTORY_LOW' ||
      'STOCK_UPDATE' ||
      'INVENTORY_UPDATE' =>
        Icons.inventory_2_outlined,
      'PRODUCT' => Icons.inventory_outlined,
      'PRICING' || 'PRICE_UPDATE' => Icons.price_change_outlined,
      'IMPORT' => Icons.upload_file_outlined,
      'OFFER' || 'SHOP_OFFER' => Icons.local_offer_outlined,
      'ORDER' || 'ORDER_NEW' => Icons.shopping_bag_outlined,
      'SUBSCRIPTION' => Icons.card_membership_outlined,
      'PAYMENT' => Icons.receipt_long_outlined,
      'POS_SYNC' => Icons.sync_outlined,
      'SHOP_VERIFICATION' => Icons.verified_user_outlined,
      'ACCOUNT' => Icons.manage_accounts_outlined,
      'ADMIN' || 'SYSTEM' => Icons.campaign_outlined,
      'SUPPORT' => Icons.support_agent_outlined,
      _ => Icons.notifications_outlined,
    };

/// The merchant notification categories shown in the Alerts filter bar.
///
/// Each category claims the backend `type` strings that belong to it, so the
/// app groups whatever the API returns and never invents a category of its
/// own. A type the backend adds later simply has no category until it is
/// registered here — it still appears under "All" and still renders its row.
enum NotificationCategory {
  inventory('Inventory', Icons.inventory_2_outlined, {
    'INVENTORY_LOW',
    'INVENTORY_UPDATE',
    'STOCK_UPDATE',
  }),
  products('Products', Icons.inventory_outlined, {'PRODUCT'}),
  pricing('Pricing', Icons.price_change_outlined, {'PRICING', 'PRICE_UPDATE'}),
  offers('Offers', Icons.local_offer_outlined, {'OFFER', 'SHOP_OFFER'}),
  imports('Imports', Icons.upload_file_outlined, {'IMPORT'}),
  pos('POS', Icons.sync_outlined, {'POS_SYNC'}),
  account('Account', Icons.manage_accounts_outlined, {
    'ACCOUNT',
    'SUBSCRIPTION',
    'PAYMENT',
    'SHOP_VERIFICATION',
  }),
  system('System', Icons.campaign_outlined, {'SYSTEM', 'ADMIN'}),
  support('Support', Icons.support_agent_outlined, {'SUPPORT'});

  const NotificationCategory(this.label, this.icon, this.types);

  /// Human-readable chip label.
  final String label;

  /// Chip icon (row icons come from [notificationIcon]).
  final IconData icon;

  /// Raw backend `type` values that belong to this category.
  final Set<String> types;

  /// True when [rawType] belongs to this category.
  bool matches(String rawType) => types.contains(rawType.toUpperCase());

  /// Category owning [rawType], or null for a type no category claims yet.
  static NotificationCategory? of(String rawType) {
    final key = rawType.toUpperCase();
    for (final category in values) {
      if (category.types.contains(key)) return category;
    }
    return null;
  }
}

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



/// Routes navigated with `go` — the shell tabs live in the indexed stack.
/// Everything else is pushed, so Back returns to the notification center.
const kNotificationTabTargets = <String>{
  Routes.dashboard,
  Routes.products,
  Routes.notifications,
  Routes.account,
};

const _deepLinkPrefix = 'hyperlocal://shopkeeper/';

/// Resolves where a notification tap should take the shopkeeper.
///
/// Precedence:
///  1. the validated notification type (+ payload event where the type alone
///     is ambiguous). The type is the authoritative signal because the
///     backend always sets it, while the deep link is an opaque hint whose
///     section may point at a coarser surface (e.g. a PRICING receipt links
///     into `products/{id}`, but the right surface is the price list).
///  2. a `hyperlocal://shopkeeper/…` deep-link section — used only when the
///     type is unknown (e.g. a type the backend added after this build).
///  3. the notification detail screen, so a tap is never a dead end.
///
/// Identifiers inside a link or payload are deliberately NOT navigated on: the
/// item screens take a full object through `extra`, and a bare id from a
/// notification is not enough to build one without inventing data. Id-level
/// navigation may only be added once the payload validates a whole object.
String notificationRouteTarget(ShopkeeperNotification notification) {
  final typeTarget = _routeTargetForType(notification);
  if (typeTarget != null) return typeTarget;

  // Unknown type — the deep-link section is the only remaining signal.
  final link = notification.deepLink;
  if (link != null && link.startsWith(_deepLinkPrefix)) {
    final section = link.substring(_deepLinkPrefix.length);
    if (section.startsWith('inventory')) return Routes.inventoryList;
    if (section.startsWith('products')) return Routes.products;
    if (section.startsWith('imports')) return Routes.importHistory;
    if (section.startsWith('offers')) return Routes.offers;
    if (section.startsWith('pos')) return Routes.pos;
    if (section.startsWith('support')) return Routes.support;
    if (section.startsWith('account')) return Routes.account;
    if (section.startsWith('shop')) return Routes.shopProfile;
    if (section.startsWith('dashboard')) return Routes.dashboard;
  }

  return Routes.notificationDetail;
}

/// Type-driven target, or null when the backend type is not recognised and
/// the caller must fall back to the deep-link section.
String? _routeTargetForType(ShopkeeperNotification notification) {
  switch (notification.type.toUpperCase()) {
    case 'INVENTORY_LOW':
      // "Low Stock → Inventory" — the low-stock scope of the inventory module.
      return Routes.lowStock;
    case 'INVENTORY_UPDATE' || 'STOCK_UPDATE':
      return Routes.inventoryList;
    case 'PRICE_UPDATE' || 'PRICING':
      // "Price Update → Product/Price" — the pricing surface, even though the
      // receipt's deep link points at `products/{id}`.
      return Routes.priceList;
    case 'PRODUCT':
      return Routes.products;
    case 'IMPORT':
      // Import results — including failures — are reviewed in Import history.
      return Routes.importHistory;
    case 'OFFER' || 'SHOP_OFFER':
      return Routes.offers;
    case 'POS_SYNC':
      return Routes.pos;
    case 'SHOP_VERIFICATION':
      return Routes.shopProfile;
    case 'ACCOUNT':
      return switch (notification.payloadEvent) {
        'PROFILE_UPDATED' => Routes.shopProfile,
        'SETTINGS_UPDATED' => Routes.shopSettings,
        _ => Routes.account,
      };
    case 'SUBSCRIPTION' || 'PAYMENT':
      return Routes.account;
    case 'SUPPORT':
      return Routes.support;
    default:
      return null;
  }
}
