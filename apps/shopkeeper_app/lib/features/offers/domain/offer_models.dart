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
  buyXGetY('BUY_X_GET_Y', 'Buy X Get Y'),
  bundle('BUNDLE', 'Bundle'),
  freeShipping('FREE_SHIPPING', 'Free shipping');

  const ShopkeeperOfferType(this.code, this.label);

  /// Backend enum value.
  final String code;

  /// Short human label for dropdowns/chips.
  final String label;

  /// PERCENTAGE requires [OfferAssignRequest.discountPercentage];
  /// FLAT requires [OfferAssignRequest.discountValue]; the rest need neither.
  bool get requiresPercentage => this == percentageDiscount;

  bool get requiresFlatValue => this == flatDiscount;
}

/// Atomic create+link payload for one offer.
class OfferAssignRequest {
  const OfferAssignRequest({
    required this.title,
    required this.offerType,
    required this.startDate,
    required this.endDate,
    required this.shopProductIds,
    this.discountValue,
    this.discountPercentage,
    this.termsConditions,
  });

  final String title;
  final ShopkeeperOfferType offerType;

  /// ₹ amount off (FLAT_DISCOUNT only).
  final double? discountValue;

  /// Percent off, 0 < value <= 100 (PERCENTAGE_DISCOUNT only).
  final double? discountPercentage;
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
    if (discountValue != null) 'discount_value': discountValue,
    if (discountPercentage != null) 'discount_percentage': discountPercentage,
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
  ) {
    if (type.requiresPercentage) {
      final pct = double.tryParse((rawPercentage ?? '').trim());
      if (pct == null || pct <= 0) return 'Discount % is required';
      if (pct > 100) return 'Discount % cannot exceed 100';
      return null;
    }
    if (type.requiresFlatValue) {
      final value = double.tryParse((rawValue ?? '').trim());
      if (value == null || value <= 0) return 'Discount amount is required';
      if (value < 0) return 'Cannot be negative';
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
