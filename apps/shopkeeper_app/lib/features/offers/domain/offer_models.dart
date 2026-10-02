/// Domain models for the shopkeeper offers feature.
///
/// Maps to the backend `POST /shopkeeper/shops/{shop_id}/offers/assign`
/// contract (`ShopkeeperOfferAssign`): create + link an offer to selected
/// shop products in a single atomic call.
library;

/// Offer types supported by the platform (backend `offer_type` enum).
enum ShopkeeperOfferType {
  percentageDiscount('PERCENTAGE_DISCOUNT', '% off'),
  flatDiscount('FLAT_DISCOUNT', '₹ off'),
  promotionalPrice('PROMOTIONAL_PRICE', 'Promo price'),
  buyXGetY('BUY_X_GET_Y', 'Buy X Get Y'),
  bundle('BUNDLE', 'Bundle'),
  freeShipping('FREE_SHIPPING', 'Free shipping');

  const ShopkeeperOfferType(this.code, this.label);

  /// Backend enum value.
  final String code;

  /// Short human label for dropdowns/chips.
  final String label;

  /// PERCENTAGE requires [OfferAssignRequest.discountPercentage];
  /// FLAT requires [OfferAssignRequest.discountValue]; PROMO requires
  /// [OfferAssignRequest.promotionalPrice]; the rest need neither.
  bool get requiresPercentage => this == percentageDiscount;

  bool get requiresFlatValue => this == flatDiscount;

  bool get requiresPromotionalPrice => this == promotionalPrice;
}

/// Atomic create+link payload for one offer.
class OfferAssignRequest {
  const OfferAssignRequest({
    required this.title,
    required this.offerType,
    required this.startDate,
    required this.endDate,
    required this.shopProductIds,
    this.status,
    this.discountValue,
    this.discountPercentage,
    this.promotionalPrice,
    this.termsConditions,
  });

  final String title;
  final ShopkeeperOfferType offerType;

  /// New offers start as drafts unless activated explicitly.
  final String? status;

  /// ₹ amount off (FLAT_DISCOUNT only).
  final double? discountValue;

  /// Percent off, 0 < value <= 100 (PERCENTAGE_DISCOUNT only).
  final double? discountPercentage;

  /// Fixed sale price (PROMOTIONAL_PRICE only).
  final double? promotionalPrice;
  final DateTime startDate;
  final DateTime endDate;

  /// Selected shop-product listings the offer applies to (1–200).
  final List<int> shopProductIds;
  final String? termsConditions;

  Map<String, dynamic> toJson() => {
    'title': title,
    'offer_type': offerType.code,
    'start_date': startDate.toUtc().toIso8601String(),
    'end_date': endDate.toUtc().toIso8601String(),
    'shop_product_ids': shopProductIds,
    if (status != null) 'status': status,
    if (discountValue != null) 'discount_value': discountValue,
    if (discountPercentage != null) 'discount_percentage': discountPercentage,
    if (promotionalPrice != null) 'promotional_price': promotionalPrice,
    if (termsConditions != null && termsConditions!.trim().isNotEmpty)
      'terms_conditions': termsConditions!.trim(),
  };
}

/// Result of a successful assignment (backend response payload).
class OfferAssignResult {
  const OfferAssignResult({
    required this.offerId,
    required this.title,
    required this.productCount,
    this.status,
  });

  final int offerId;
  final String title;
  final int productCount;
  final String? status;

  factory OfferAssignResult.fromJson(Map<String, dynamic> json) =>
      OfferAssignResult(
        offerId:
            (json['offer_id'] as num?)?.toInt() ??
            (json['id'] as num?)?.toInt() ??
            0,
        title: json['title'] as String? ?? '',
        productCount: (json['product_count'] as num?)?.toInt() ?? 0,
        status: json['status'] as String?,
      );
}

/// One offer row as returned by
/// `GET /shopkeeper/shops/{shop_id}/offers`.
///
/// [displayStatus] is derived **server-side** from the date window, so the
/// Active / Scheduled / Expired tabs never re-derive dates on the client and
/// can never disagree with the backend.
class OfferSummary {
  const OfferSummary({
    required this.id,
    required this.title,
    required this.offerType,
    required this.status,
    required this.displayStatus,
    required this.productCount,
    this.description,
    this.discountValue,
    this.discountPercentage,
    this.promotionalPrice,
    this.startDate,
    this.endDate,
    this.isVisible = true,
    this.termsConditions,
  });

  final int id;
  final String title;
  final String? description;

  /// Raw backend enum, e.g. `PERCENTAGE_DISCOUNT`.
  final String offerType;

  /// Stored status: `ACTIVE` | `DRAFT` | `DISABLED` | `EXPIRED` (may be PAUSED etc.).
  final String status;

  /// Shopkeeper-facing bucket: `ACTIVE` | `SCHEDULED` | `EXPIRED` | `DRAFT` | `DISABLED`.
  final String displayStatus;

  /// ₹ amount off (FLAT_DISCOUNT).
  final double? discountValue;

  /// Percent off (PERCENTAGE_DISCOUNT).
  final double? discountPercentage;

  /// Fixed sale price (PROMOTIONAL_PRICE).
  final double? promotionalPrice;

  final DateTime? startDate;
  final DateTime? endDate;
  final bool isVisible;
  final String? termsConditions;

  /// How many shop products the offer is linked to.
  final int productCount;

  /// True when the offer is in its live window right now.
  bool get isLive => displayStatus == 'ACTIVE';

  /// True when the window has not started yet.
  bool get isScheduled => displayStatus == 'SCHEDULED';

  /// True when the offer is over (status EXPIRED or the window closed).
  bool get isExpired => displayStatus == 'EXPIRED';

  /// True when the offer is still a draft and not published.
  bool get isDraft => displayStatus == 'DRAFT';

  /// True while the offer is disabled and hidden from customers.
  bool get isDisabled => displayStatus == 'DISABLED';

  /// Lifecycle moves the backend accepts, mirroring
  /// `_OFFER_STATUS_TRANSITIONS` in `shopkeeper_service.py`.
  ///
  /// Keyed by the **stored** [status] (not [displayStatus]) because that is
  /// exactly what the server inspects before allowing a move. EXPIRED and
  /// CANCELLED are absent on purpose: they are terminal, so no move is legal.
  /// This only hides buttons the server would reject — the backend still
  /// re-validates every transition.
  static const Map<String, Set<String>> _allowedMoves = {
    'DRAFT': {'ACTIVE', 'DISABLED'},
    'ACTIVE': {'PAUSED', 'DISABLED', 'CANCELLED', 'EXPIRED'},
    'PAUSED': {'ACTIVE', 'DISABLED', 'CANCELLED'},
    'DISABLED': {'DRAFT', 'ACTIVE'},
  };

  /// True when the backend would accept moving this offer to [target]
  /// (a raw `OfferStatus` value such as `ACTIVE` or `DISABLED`).
  bool canTransitionTo(String target) =>
      _allowedMoves[status]?.contains(target) ?? false;

  /// True when the offer can be activated right now.
  bool get canActivate => canTransitionTo('ACTIVE');

  /// True when the offer can be deactivated (disabled) right now.
  bool get canDisable => canTransitionTo('DISABLED');

  /// Friendly name for the backend `offer_type` enum.
  String get offerTypeLabel {
    for (final type in ShopkeeperOfferType.values) {
      if (type.code == offerType) return type.label;
    }
    return offerType;
  }

  /// The deduction as the shopkeeper would say it, e.g. `15% off` / `₹50 off`.
  String get discountLabel {
    if (discountPercentage != null && discountPercentage! > 0) {
      return '${_trimNumber(discountPercentage!)}% off';
    }
    if (promotionalPrice != null && promotionalPrice! > 0) {
      return 'Promo ₹${_trimNumber(promotionalPrice!)}';
    }
    if (discountValue != null && discountValue! > 0) {
      return '₹${_trimNumber(discountValue!)} off';
    }
    return offerTypeLabel;
  }

  /// Validity window, e.g. `12 Jan – 20 Jan 2026`.
  String get windowLabel {
    final start = startDate;
    final end = endDate;
    if (start == null || end == null) return '';
    return '${_formatDay(start)}  –  ${_formatDay(end)}';
  }

  factory OfferSummary.fromJson(Map<String, dynamic> json) => OfferSummary(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        description: json['description'] as String?,
        offerType: json['offer_type'] as String? ?? '',
        status: json['status'] as String? ?? 'DRAFT',
        displayStatus:
            json['display_status'] as String? ?? json['status'] as String? ?? 'DRAFT',
        discountValue: (json['discount_value'] as num?)?.toDouble(),
        discountPercentage: (json['discount_percentage'] as num?)?.toDouble(),
        promotionalPrice: (json['promotional_price'] as num?)?.toDouble(),
        startDate: _parseDate(json['start_date']),
        endDate: _parseDate(json['end_date']),
        isVisible: json['is_visible'] as bool? ?? true,
        termsConditions: json['terms_conditions'] as String?,
        productCount: (json['product_count'] as num?)?.toInt() ?? 0,
      );

  static DateTime? _parseDate(Object? raw) {
    if (raw is DateTime) return raw;
    if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw)?.toLocal();
    return null;
  }
}

/// Result of `GET /shopkeeper/shops/{shop_id}/offers`.
class OfferListPage {
  const OfferListPage({required this.items, required this.count});

  final List<OfferSummary> items;
  final int count;

  bool get isEmpty => items.isEmpty;

  factory OfferListPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final items = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(OfferSummary.fromJson)
            .toList(growable: false)
        : <OfferSummary>[];
    return OfferListPage(
      items: items,
      count: (json['count'] as num?)?.toInt() ?? items.length,
    );
  }
}

/// Drops the trailing `.0` from whole numbers so `15.0%` reads as `15%`.
String _trimNumber(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

const List<String> _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Compact `12 Jan 2026` formatting (no intl dependency in this app).
String _formatDay(DateTime date) =>
    '${date.day} ${_monthNames[date.month - 1]} ${date.year}';

/// Client-side validation mirroring the backend `ShopkeeperOfferAssign`
/// rules. Returns an error message, or null when the field is valid.
class OfferValidators {
  OfferValidators._();

  static String? title(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Offer title is required';
    if (value.length > 255) return 'Title is too long';
    return null;
  }

  static String? discount(
    ShopkeeperOfferType type,
    String? rawPercentage,
    String? rawValue,
    [String? rawPromo]
  ) {
    if (type.requiresPercentage) {
      final pct = double.tryParse((rawPercentage ?? '').trim());
      if (pct == null || pct <= 0) return 'Discount % is required';
      if (pct > 100) return 'Discount % cannot exceed 100';
      return null;
    }
    if (type.requiresFlatValue) {
      final value = double.tryParse((rawValue ?? '').trim());
      if (value == null) return 'Discount amount is required';
      // Order matters: the negative case used to be unreachable, because the
      // `<= 0` branch above returned first and claimed a negative flat discount
      // was merely "required". Both are refused, but they are different
      // mistakes and the shopkeeper deserves to be told which one they made.
      if (value < 0) return 'Cannot be negative';
      // A ₹0 flat discount saves the customer nothing, so it is treated as
      // "not filled in" rather than accepted as a live offer.
      if (value == 0) return 'Discount amount is required';
      return null;
    }
    if (type.requiresPromotionalPrice) {
      final promo = double.tryParse(((rawPromo ?? rawValue ?? '')).trim());
      if (promo == null || promo <= 0) return 'Promotional price is required';
      return null;
    }
    return null;
  }

  static String? period(DateTime? start, DateTime? end) {
    if (start == null || end == null) return 'Select both dates';
    if (!end.isAfter(start)) return 'End date must be after the start date';
    return null;
  }
}
