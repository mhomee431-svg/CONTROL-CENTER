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

/// Read-only customer-facing product reference extracted from a notification
/// payload.
///
/// Ids are treated as *untrusted input*: only validated values (non-empty,
/// route-safe, and optionally carrying a numeric backend id) are exposed, so
/// navigation can never be steered by a malformed payload.
class NotificationProductRef {
  const NotificationProductRef({required this.targetId, this.productMasterId});

  /// Opaque token used to build the `/product/:id` route path.
  /// Always route-safe; empty when no usable product reference exists.
  final String targetId;

  /// Validated `product_master_id` from the payload, or null when absent /
  /// non-numeric. Used to confirm the notification really points at a
  /// Product Master instead of duplicating one client-side.
  final int? productMasterId;

  bool get isValid => targetId.isNotEmpty;
}

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

  /// Validated backend `product_master_id`, when the payload carried one.
  /// Lets the product screen confirm the master before rendering so the
  /// client never invents or duplicates a Product Master.
  final int? productMasterId;

  const NotificationDeepLink({
    this.targetType = DeepLinkTargetType.none,
    this.targetId = '',
    this.expiresAt,
    this.productMasterId,
  });

  /// Customer-facing product reference, or null when this link does not
  /// point at a product (or its id failed validation).
  NotificationProductRef? get productRef {
    if (targetType != DeepLinkTargetType.product) return null;
    if (!_safeIdPattern.hasMatch(targetId)) return null;
    return NotificationProductRef(
      targetId: targetId,
      productMasterId: productMasterId,
    );
  }

  /// Ids are opaque tokens used to build route paths — only allow
  /// characters that cannot alter the route structure.
  static final RegExp _safeIdPattern = RegExp(r'^[A-Za-z0-9_\-]{1,64}$');

  /// Validated numeric backend ids (e.g. `product_master_id`, `shop_id`).
  /// Only strictly positive whole numbers count; anything else (missing,
  /// wrong type, zero/negative, fractional) is treated as absent so a
  /// malformed payload can never steer navigation or fabricate an entity.
  static int? validatedId(Object? raw) {
    if (raw is int && raw > 0) return raw;
    if (raw is num && raw > 0 && raw == raw.round()) return raw.round();
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      final parsed = int.tryParse(trimmed);
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }

  /// Parses the loosely-typed `payload` field delivered by the backend.
  ///
  /// Accepts either a `Map<String, dynamic>` or a JSON-encoded string
  /// (the API contract ships the payload as a string). Never throws —
  /// any parsing problem yields a non-navigable link.
  factory NotificationDeepLink.fromPayload(
    Object? payload, {
    String? deepLink,
  }) {
    final map = _payloadMap(payload);
    if (map == null) {
      final hinted = _fromDeepLinkHint(null, deepLink);
      return hinted ?? const NotificationDeepLink();
    }

    String? text(Object? v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    final expiresAt = _parseExpiresAt(map);
    // Backend key for the canonical master id (PRICE_DROP /
    // PRODUCT_AVAILABLE carry `product_master_id`); older / mock payloads
    // may use `product_id` instead.
    final productMasterId =
        validatedId(map['product_master_id']) ?? validatedId(map['product_id']);
    final productId = text(map['product_id']) ??
        text(map['productId']) ??
        (productMasterId != null ? '$productMasterId' : null) ??
        '';
    final offerId = text(map['offer_id']) ??
        text(map['offerId']) ??
        text(map['deal_id']) ??
        text(map['dealId']) ??
        '';
    final shopId = text(map['shop_id']) ?? text(map['shopId']) ?? '';

    // A payload id is only usable when it ALSO passes the route-safety
    // check — otherwise a hostile payload (e.g. `../../admin`) must keep
    // the whole link non-navigable and must never fall through to the URI.
    final safeProductId =
        productId.isNotEmpty && _safeIdPattern.hasMatch(productId)
            ? productId
            : '';
    final safeOfferId =
        offerId.isNotEmpty && _safeIdPattern.hasMatch(offerId) ? offerId : '';
    final safeShopId =
        shopId.isNotEmpty && _safeIdPattern.hasMatch(shopId) ? shopId : '';
    final payloadHadIdKeys = productId.isNotEmpty ||
        offerId.isNotEmpty ||
        shopId.isNotEmpty ||
        map.containsKey('product_master_id');

    // Priority: most specific target first.
    if (safeProductId.isNotEmpty) {
      return NotificationDeepLink(
        targetType: DeepLinkTargetType.product,
        targetId: safeProductId,
        expiresAt: expiresAt,
        productMasterId: productMasterId,
      );
    }
    if (safeOfferId.isNotEmpty) {
      return NotificationDeepLink(
        targetType: DeepLinkTargetType.offer,
        targetId: safeOfferId,
        expiresAt: expiresAt,
      );
    }
    if (safeShopId.isNotEmpty) {
      return NotificationDeepLink(
        targetType: DeepLinkTargetType.shop,
        targetId: safeShopId,
        expiresAt: expiresAt,
      );
    }
    if (payloadHadIdKeys) {
      // Payload carried ids but none validated — never trust the raw URI.
      return NotificationDeepLink(expiresAt: expiresAt);
    }
    // No usable payload ids — but ONLY when the payload truly carried no id
    // keys at all. When the payload HAS id keys whose values failed
    // validation, the link stays non-navigable: a hostile or corrupt payload
    // must never fall through to the raw URI.
    final hinted = _fromDeepLinkHint(map, deepLink, expiresAt: expiresAt);
    return hinted ?? NotificationDeepLink(expiresAt: expiresAt);
  }

  /// Backend `deep_link` URIs (`hyperlocal://product/42`,
  /// `hyperlocal://shop/7`, `hyperlocal://offers/3`) are validated like any
  /// other untrusted input: only a known section + a route-safe id counts.
  ///
  /// Navigation always requires a VALIDATED payload id — the URI hint is
  /// only trusted when the payload carried no usable ids at all (legacy
  /// rows), and never when the payload exists but its ids failed validation
  /// (a hostile or corrupt payload must not fall through to the raw URI).
  static NotificationDeepLink? _fromDeepLinkHint(
    Map<String, dynamic>? map,
    String? deepLink, {
    DateTime? expiresAt,
  }) {
    final hasPayloadIds = map != null &&
        (map.containsKey('product_id') ||
            map.containsKey('productId') ||
            map.containsKey('product_master_id') ||
            map.containsKey('offer_id') ||
            map.containsKey('offerId') ||
            map.containsKey('deal_id') ||
            map.containsKey('dealId') ||
            map.containsKey('shop_id') ||
            map.containsKey('shopId'));
    if (hasPayloadIds) return null;
    if (deepLink == null) return null;
    final rawLink = deepLink.trim();
    // `Uri` silently normalizes `.`/`..` path segments away, so
    // `hyperlocal://product/../../admin` would collapse into a
    // seemingly-valid single-token link. Inspect the RAW path first so a
    // link that climbs out of its own section is rejected before
    // normalization can hide the escape.
    final rawPath = rawLink.split('#').first.split('?').first;
    if (rawPath.split('/').any((s) => s == '.' || s == '..')) return null;
    final uri = Uri.tryParse(rawLink);
    if (uri == null || uri.scheme != 'hyperlocal' || uri.host.isEmpty) {
      return null;
    }
    // A URI whose id is not a single opaque token is hostile: the id must be
    // a single opaque token, never a path.
    final segments =
        uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
    if (segments.length != 1) return null;
    if (segments.any((s) => s.trim() == '.' || s.trim() == '..')) return null;
    final id = segments.last.trim();
    if (!_safeIdPattern.hasMatch(id)) return null;
    switch (uri.host.toLowerCase()) {
      case 'product':
        return NotificationDeepLink(
          targetType: DeepLinkTargetType.product,
          targetId: id,
          expiresAt: expiresAt,
          productMasterId: validatedId(id),
        );
      case 'shop':
        return NotificationDeepLink(
          targetType: DeepLinkTargetType.shop,
          targetId: id,
          expiresAt: expiresAt,
        );
      case 'offers':
      case 'offer':
        return NotificationDeepLink(
          targetType: DeepLinkTargetType.offer,
          targetId: id,
          expiresAt: expiresAt,
        );
      default:
        return null;
    }
  }

  static Map<String, dynamic>? _payloadMap(Object? payload) {
    if (payload == null) return null;
    if (payload is Map<String, dynamic>) return payload;
    if (payload is Map) {
      return payload.map((k, v) => MapEntry(k.toString(), v));
    }
    if (payload is String) {
      final trimmed = payload.trim();
      if (trimmed.isEmpty) return null;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static DateTime? _parseExpiresAt(Map<String, dynamic>? map) {
    if (map == null) return null;
    final raw = map['expires_at'] ?? map['expiresAt'];
    if (raw is DateTime) return raw;
    if (raw is int && raw > 0) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }
    if (raw is num && raw > 0) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    }
    if (raw is String && raw.trim().isNotEmpty) {
      final asMillis = int.tryParse(raw.trim());
      if (asMillis != null && asMillis > 0) {
        return DateTime.fromMillisecondsSinceEpoch(asMillis);
      }
      return DateTime.tryParse(raw.trim());
    }
    return null;
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
      other.expiresAt == expiresAt &&
      other.productMasterId == productMasterId;

  @override
  int get hashCode =>
      Object.hash(targetType, targetId, expiresAt, productMasterId);
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
      deepLink: NotificationDeepLink.fromPayload(
        json['payload'],
        deepLink: json['deep_link']?.toString(),
      ),
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