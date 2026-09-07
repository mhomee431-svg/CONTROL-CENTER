import 'dart:convert';

/// Types of notifications the customer can receive.
///
/// Customer-facing alert taxonomy:
///  - [priceDrop]         – a watched product got cheaper nearby
///  - [productAvailable]  – an out-of-stock product is available again
///  - [offer]             – promotional / deal announcements
///  - [shopUpdate]        – news from a followed shop (hours, new items…)
///  - [system]            – service/account messages
///  - [orderUpdate]       – reserved for the future orders flow
enum NotificationType {
  priceDrop,
  productAvailable,
  offer,
  shopUpdate,
  system,
  orderUpdate;

  /// Maps a backend `type` string (see API_CONTRACT §21) to a
  /// [NotificationType]. Unknown values degrade safely to [system].
  static NotificationType fromApi(String? raw) {
    switch (raw) {
      case 'price_alert':
      case 'price_drop':
        return NotificationType.priceDrop;
      case 'availability_alert':
      case 'availability':
      case 'product_available':
      case 'in_stock':
        return NotificationType.productAvailable;
      case 'promotional':
      case 'offer':
      case 'deal':
      case 'deal_alert':
        return NotificationType.offer;
      case 'shop_update':
      case 'shop':
        return NotificationType.shopUpdate;
      case 'order_update':
        return NotificationType.orderUpdate;
      default:
        return NotificationType.system;
    }
  }

  /// Canonical backend string for this type.
  String toApi() {
    switch (this) {
      case NotificationType.priceDrop:
        return 'price_alert';
      case NotificationType.productAvailable:
        return 'availability_alert';
      case NotificationType.offer:
        return 'promotional';
      case NotificationType.shopUpdate:
        return 'shop_update';
      case NotificationType.orderUpdate:
        return 'order_update';
      case NotificationType.system:
        return 'system';
    }
  }
}

/// Where a notification should take the customer when tapped.
enum DeepLinkTargetType { none, product, shop, offer }

/// A parsed, validated navigation target extracted from a notification
/// payload.
///
/// Deep links are treated as *untrusted input*: malformed ids, unknown
/// targets and expired links are all reported through [isValid] so the
/// UI can fall back to a safe "no longer available" experience instead of
/// crashing or navigating into a broken screen.
class NotificationDeepLink {
  final DeepLinkTargetType targetType;

  /// Identifier of the target entity (empty when [targetType] is
  /// [DeepLinkTargetType.none]).
  final String targetId;

  /// Optional instant after which the link must be considered stale
  /// (e.g. an offer that has ended).
  final DateTime? expiresAt;

  const NotificationDeepLink({
    this.targetType = DeepLinkTargetType.none,
    this.targetId = '',
    this.expiresAt,
  });

  /// Ids are opaque tokens used to build route paths — only allow
  /// characters that cannot alter the route structure.
  static final RegExp _safeIdPattern = RegExp(r'^[A-Za-z0-9_\-]{1,64}$');

  /// Parses the loosely-typed `payload` field delivered by the backend.
  ///
  /// Accepts either a `Map<String, dynamic>` or a JSON-encoded string
  /// (the API contract ships the payload as a string). Never throws —
  /// any parsing problem yields a non-navigable link.
  factory NotificationDeepLink.fromPayload(dynamic payload) {
    Map<String, dynamic> map;
    if (payload is Map<String, dynamic>) {
      map = payload;
    } else if (payload is String && payload.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(payload);
        if (decoded is! Map<String, dynamic>) {
          return const NotificationDeepLink();
        }
        map = decoded;
      } catch (_) {
        return const NotificationDeepLink();
      }
    } else {
      return const NotificationDeepLink();
    }

    String readId(List<String> keys) {
      for (final key in keys) {
        final value = map[key];
        if (value != null) {
          final id = value.toString().trim();
          if (id.isNotEmpty) return id;
        }
      }
      return '';
    }

    final productId = readId(['product_id', 'productId']);
    final shopId = readId(['shop_id', 'shopId']);
    final offerId = readId(['offer_id', 'offerId', 'deal_id', 'dealId']);
    final expiresRaw = map['expires_at'] ?? map['expiresAt'];
    DateTime? expiresAt;
    if (expiresRaw is String) {
      expiresAt = DateTime.tryParse(expiresRaw);
    } else if (expiresRaw is int) {
      expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresRaw);
    }

    // Priority: most specific target first.
    if (productId.isNotEmpty) {
      return NotificationDeepLink(
        targetType: DeepLinkTargetType.product,
        targetId: productId,
        expiresAt: expiresAt,
      );
    }
    if (offerId.isNotEmpty) {
      return NotificationDeepLink(
        targetType: DeepLinkTargetType.offer,
        targetId: offerId,
        expiresAt: expiresAt,
      );
    }
    if (shopId.isNotEmpty) {
      return NotificationDeepLink(
        targetType: DeepLinkTargetType.shop,
        targetId: shopId,
        expiresAt: expiresAt,
      );
    }
    return NotificationDeepLink(expiresAt: expiresAt);
  }

  /// Whether tapping the notification can safely navigate somewhere.
  ///
  /// A link is invalid when it has no target, its id is malformed or it
  /// has expired.
  bool isValid({DateTime? now}) {
    final at = now ?? DateTime.now();
    if (targetType == DeepLinkTargetType.none) return false;
    if (!_safeIdPattern.hasMatch(targetId)) return false;
    if (expiresAt != null && expiresAt!.isBefore(at)) return false;
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationDeepLink &&
      other.targetType == targetType &&
      other.targetId == targetId &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(targetType, targetId, expiresAt);
}

class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime timestamp;
  final bool isRead;
  final NotificationType type;

  /// Parsed navigation target — check [NotificationDeepLink.isValid]
  /// before navigating.
  final NotificationDeepLink deepLink;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    this.isRead = false,
    this.type = NotificationType.system,
    this.deepLink = const NotificationDeepLink(),
  });

  /// Builds a notification from the backend list payload
  /// (API_CONTRACT §21.1). Tolerates missing/malformed fields.
  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      timestamp:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      isRead: json['is_read'] == true,
      type: NotificationType.fromApi(json['type']?.toString()),
      deepLink: NotificationDeepLink.fromPayload(json['payload']),
    );
  }

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      title: title,
      body: body,
      timestamp: timestamp,
      isRead: isRead ?? this.isRead,
      type: type,
      deepLink: deepLink,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppNotification &&
      other.id == id &&
      other.title == title &&
      other.body == body &&
      other.timestamp == timestamp &&
      other.isRead == isRead &&
      other.type == type &&
      other.deepLink == deepLink;

  @override
  int get hashCode =>
      Object.hash(id, title, body, timestamp, isRead, type, deepLink);
}