import 'package:flutter/material.dart';

import '../../auth/domain/auth_models.dart';

export '../../auth/domain/auth_models.dart' show ShopSummary;

/// Verification lifecycle for a shop
/// (PENDING → SUBMITTED → UNDER_REVIEW → VERIFIED / REJECTED / EXPIRED).

class VerificationInfo {
  const VerificationInfo({
    required this.status,
    this.reviewNotes,
    this.submittedAt,
    this.reviewedAt,
    this.verifiedAt,
    this.expiresAt,
  });

  final String status;
  final String? reviewNotes;

  /// Lifecycle timestamps straight from the server (ISO-8601 strings).
  /// The Shop Status screen renders this timeline — nothing is derived.
  final String? submittedAt;
  final String? reviewedAt;
  final String? verifiedAt;
  final String? expiresAt;

  bool get isVerified => status == 'VERIFIED';
  bool get isRejected => status == 'REJECTED';
  bool get isPending => !isVerified && !isRejected;

  factory VerificationInfo.fromJson(Map<String, dynamic>? json) =>
      VerificationInfo(
        status: (json?['status'] as String?) ?? 'PENDING',
        reviewNotes: json?['review_notes'] as String?,
        submittedAt: json?['submitted_at'] as String?,
        reviewedAt: json?['reviewed_at'] as String?,
        verifiedAt: json?['verified_at'] as String?,
        expiresAt: json?['expires_at'] as String?,
      );
}

/// Business subscription attached to a shop.
class SubscriptionInfo {
  const SubscriptionInfo({required this.status, this.plan});

  final String status;
  final String? plan;

  bool get isActive => status == 'ACTIVE';
  bool get hasSubscription => status != 'NONE';

  factory SubscriptionInfo.fromJson(Map<String, dynamic>? json) =>
      SubscriptionInfo(
        status: (json?['status'] as String?) ?? 'NONE',
        plan: json?['plan'] as String?,
      );
}

/// Backend-driven feature flags for one shop (spec section 103).
///
/// Single source of truth: the backend derives these ONLY from the resolved
/// subscription entitlements (`derive_shop_capabilities`). The app never
/// duplicates plan rules - it only reads these four flags to conditionally
/// show functionality. Display hints only; the backend stays authoritative
/// (403 on actual violations, surfaced via `ApiException.isEntitlementDenied`).
class ShopCapabilities {
  const ShopCapabilities({
    this.canUsePos = true,
    this.canUploadExcel = true,
    this.canCreateOffers = true,
    this.canViewReports = true,
  });

  /// POS integrations allowed (`pos_support` entitlement).
  final bool canUsePos;

  /// Excel/bulk import allowed (`BULK_IMPORT` in `listing_features`).
  final bool canUploadExcel;

  /// Offer creation allowed (`offers` entitlement).
  final bool canCreateOffers;

  /// Reports / analytics allowed (`analytics` entitlement).
  final bool canViewReports;

  /// Permissive legacy default: absent block (old backend / cache) never
  /// locks the shopkeeper out of their own screens.
  factory ShopCapabilities.fromJson(Map<String, dynamic>? json) =>
      ShopCapabilities(
        canUsePos: (json?['canUsePos'] as bool?) ?? true,
        canUploadExcel: (json?['canUploadExcel'] as bool?) ?? true,
        canCreateOffers: (json?['canCreateOffers'] as bool?) ?? true,
        canViewReports: (json?['canViewReports'] as bool?) ?? true,
      );

  Map<String, dynamic> toJson() => {
        'canUsePos': canUsePos,
        'canUploadExcel': canUploadExcel,
        'canCreateOffers': canCreateOffers,
        'canViewReports': canViewReports,
      };
}

/// Full shop profile payload (GET /shopkeeper/shops/{id}).
class ShopDetail {
  const ShopDetail({
    required this.summary,
    this.description,
    this.tagline,
    this.phone,
    this.email,
    this.websiteUrl,
    this.logoUrl,
    required this.verification,
    required this.subscription,
    this.capabilities = const ShopCapabilities(),
    required this.rating,
    required this.reviewCount,
    this.isAcceptingOrders = true,
    this.isDeliveryAvailable = true,
    this.isPickupAvailable = true,
    this.isOpen24x7 = false,
    this.minOrderAmount = 0,
    this.deliveryRadiusKm = 5,
    this.deliveryFee = 0,
    this.freeDeliveryAbove = 0,
    // Location metadata (Phase: Shop Location System).
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.locationVerified = false,
    this.locationStatus,
    this.locationSource,
    this.locationType,
    this.locationCapturedAt,
    // Business-information payload (`GET /shopkeeper/shops/{id}`).
    this.alternatePhone,
    this.whatsappNumber,
    this.gstin,
    this.createdAt,
    this.address,
    this.hours = const <ShopHourEntry>[],
  });

  final ShopSummary summary;
  final String? description;
  final String? tagline;
  final String? phone;
  final String? email;
  final String? websiteUrl;
  final String? logoUrl;
  final VerificationInfo verification;
  final SubscriptionInfo subscription;

  /// Backend-driven feature flags (spec section 103). Absent on old
  /// payloads -> permissive default, never a lock-out.
  final ShopCapabilities capabilities;
  final double rating;
  final int reviewCount;

  // Operational settings
  final bool isAcceptingOrders;
  final bool isDeliveryAvailable;
  final bool isPickupAvailable;
  final bool isOpen24x7;
  final double minOrderAmount;
  final double deliveryRadiusKm;
  final double deliveryFee;
  final double freeDeliveryAbove;

  // Location metadata (Phase: Shop Location System).
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final bool locationVerified;
  final String? locationStatus;
  final String? locationSource;
  final String? locationType;
  final String? locationCapturedAt;

  // Business-information payload (Phase: Shop Profile module).
  final String? alternatePhone;
  final String? whatsappNumber;
  final String? gstin;

  /// ISO-8601 "member since" straight from the server.
  final String? createdAt;

  /// The shop's address when the payload carries one (the registration
  /// response does; the detail endpoint may omit it).
  final ShopAddress? address;

  /// Weekly operating hours when the payload carries them (the dedicated
  /// `GET /shops/{id}/hours` endpoint is the authoritative source).
  final List<ShopHourEntry> hours;

  /// Whether the shop has stored coordinates on the server.
  bool get hasLocation =>
      latitude != null && longitude != null && hasValidCoordinates;

  bool get hasValidCoordinates =>
      (latitude?.abs() ?? 0) <= 90 && (longitude?.abs() ?? 0) <= 180;

  /// `12.345678, 78.123456` — for the Shop Location screen.
  String get coordinatesLabel => latitude == null || longitude == null
      ? '—'
      : '${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}';

  /// Human category label (`PHARMACY` → `Pharmacy`) — `—` when unset.
  String get categoryLabel =>
      summary.category == null || summary.category!.isEmpty
          ? '—'
          : humanizeCode(summary.category!);

  factory ShopDetail.fromJson(Map<String, dynamic> json) => ShopDetail(
        summary: ShopSummary.fromJson(json),
        description: json['description'] as String?,
        tagline: json['tagline'] as String?,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        websiteUrl: json['website_url'] as String?,
        logoUrl: json['logo_url'] as String?,
        verification: VerificationInfo.fromJson(
            json['verification'] as Map<String, dynamic>?),
        subscription: SubscriptionInfo.fromJson(
            json['subscription'] as Map<String, dynamic>?),
        capabilities: ShopCapabilities.fromJson(
            json['capabilities'] as Map<String, dynamic>?),
        rating: (json['rating'] as num?)?.toDouble() ?? 0,
        reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
        isAcceptingOrders: json['is_accepting_orders'] as bool? ?? true,
        isDeliveryAvailable: json['is_delivery_available'] as bool? ?? true,
        isPickupAvailable: json['is_pickup_available'] as bool? ?? true,
        isOpen24x7: json['is_open_24x7'] as bool? ?? false,
        minOrderAmount: (json['min_order_amount'] as num?)?.toDouble() ?? 0,
        deliveryRadiusKm: (json['delivery_radius_km'] as num?)?.toDouble() ?? 5,
        deliveryFee: (json['delivery_fee'] as num?)?.toDouble() ?? 0,
        freeDeliveryAbove: (json['free_delivery_above'] as num?)?.toDouble() ?? 0,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        accuracyMeters: (json['accuracy_meters'] as num?)?.toDouble(),
        locationVerified: json['location_verified'] as bool? ?? false,
        locationStatus: json['location_status'] as String?,
        locationSource: json['location_source'] as String?,
        locationType: json['location_type'] as String?,
        locationCapturedAt: json['location_captured_at'] as String?,
        alternatePhone: json['alternate_phone'] as String?,
        whatsappNumber: json['whatsapp_number'] as String?,
        gstin: json['gstin'] as String?,
        createdAt: json['created_at'] as String?,
        address: ShopAddress.fromJson(
          json['address'] as Map<String, dynamic>?,
        ),
        hours: ((json['hours'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ShopHourEntry.fromJson)
            .toList(growable: false),
      );
}

/// One weekday of the shop's weekly schedule
/// (`GET/PUT /shopkeeper/shops/{id}/hours`; `day_of_week` 0=Monday..6=Sunday).
class ShopHourEntry {
  const ShopHourEntry({
    required this.dayOfWeek,
    required this.openTime,
    required this.closeTime,
    required this.isClosed,
  });

  /// 0 = Monday … 6 = Sunday (server contract, see `is_shop_open`).
  final int dayOfWeek;
  final String? openTime;
  final String? closeTime;
  final bool isClosed;

  /// `Monday` … `Sunday`.
  String get dayLabel => kWeekDayLabels[dayOfWeek.clamp(0, 6)];

  /// `09:00 – 21:00` or `Closed` — display only, never derived further.
  String get hoursLabel => isClosed
      ? 'Closed'
      : '${openTime ?? '—'} – ${closeTime ?? '—'}';

  /// `HH:MM` in, `HH:MM` out (the server accepts `HH:MM` and `HH:MM:SS`).
  static String? _normalizeTime(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final parts = value.split(':');
    if (parts.length >= 2) return '${parts[0]}:${parts[1]}';
    return value;
  }

  factory ShopHourEntry.fromJson(Map<String, dynamic> json) => ShopHourEntry(
        dayOfWeek: (json['day_of_week'] as num?)?.toInt() ?? 0,
        openTime: _normalizeTime(json['open_time']),
        closeTime: _normalizeTime(json['close_time']),
        isClosed: json['is_closed'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'day_of_week': dayOfWeek,
        'open_time': openTime ?? '09:00',
        'close_time': closeTime ?? '21:00',
        'is_closed': isClosed,
      };

  ShopHourEntry copyWith({String? openTime, String? closeTime, bool? isClosed}) =>
      ShopHourEntry(
        dayOfWeek: dayOfWeek,
        openTime: openTime ?? this.openTime,
        closeTime: closeTime ?? this.closeTime,
        isClosed: isClosed ?? this.isClosed,
      );

  /// A full-open week at the server's default 09:00–21:00 (registration
  /// default on the backend) — used to seed the editor when the shop has no
  /// stored rows yet.
  static List<ShopHourEntry> defaultWeek() => [
        for (var day = 0; day < 7; day++)
          ShopHourEntry(
            dayOfWeek: day,
            openTime: '09:00',
            closeTime: '21:00',
            isClosed: false,
          ),
      ];

  /// Normalizes a server week to exactly 7 rows (0..6), defaulting missing
  /// days so the editor is never missing a weekday.
  static List<ShopHourEntry> normalizeWeek(List<ShopHourEntry> hours) {
    final byDay = {for (final h in hours) h.dayOfWeek: h};
    return [
      for (var day = 0; day < 7; day++)
        byDay[day] ?? ShopHourEntry(dayOfWeek: day, openTime: '09:00', closeTime: '21:00', isClosed: true),
    ];
  }
}

/// Weekday labels for the `day_of_week` 0=Monday..6=Sunday server contract.
const kWeekDayLabels = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// The shop's registered address (registration payload; the detail endpoint
/// omits it, so every field is tolerant).
class ShopAddress {
  const ShopAddress({
    this.line1,
    this.line2,
    this.landmark,
    this.city,
    this.state,
    this.pincode,
    this.country,
  });

  final String? line1;
  final String? line2;
  final String? landmark;
  final String? city;
  final String? state;
  final String? pincode;
  final String? country;

  bool get hasContent => [
        line1,
        line2,
        landmark,
        city,
        state,
        pincode,
        country,
      ].any((part) => part != null && part.trim().isNotEmpty);

  /// One-line display form, skipping empty parts.
  String get formatted => [
        line1,
        line2,
        landmark,
        city,
        state,
        pincode,
        country,
      ].whereType<String>().map((p) => p.trim()).where((p) => p.isNotEmpty).join(', ');

  factory ShopAddress.fromJson(Map<String, dynamic>? json) => ShopAddress(
        line1: json?['line1'] as String? ?? json?['address_line1'] as String?,
        line2: json?['line2'] as String? ?? json?['address_line2'] as String?,
        landmark: json?['landmark'] as String?,
        city: json?['city'] as String?,
        state: json?['state'] as String?,
        pincode: json?['pincode'] as String?,
        country: json?['country'] as String?,
      );
}

/// `PHARMACY_HEALTHCARE` → `Pharmacy healthcare` — display only.
String humanizeCode(String code) {
  final lowered = code.replaceAll('_', ' ').toLowerCase().trim();
  if (lowered.isEmpty) return code;
  return lowered[0].toUpperCase() + lowered.substring(1);
}

/// Static category choices for shop registration forms.
const kShopCategories = <String>[
  'GROCERY',
  'ELECTRONICS',
  'PHARMACY',
  'HARDWARE',
  'FASHION',
  'RESTAURANT',
  'BAKERY',
  'DAIRY',
  'MEAT',
  'VEGETABLES',
  'STATIONERY',
  'TOYS',
  'BEAUTY',
  'OTHER',
];

// ── Merchant categories & category requirements (backend-driven) ────────────

/// A merchant category shown in the shop-registration wizard dropdown.
///
/// Loaded from `GET /shopkeeper/businesses/categories` — the app never
/// hardcodes category codes.
class MerchantCategoryOption {
  const MerchantCategoryOption({
    required this.code,
    required this.name,
    this.description,
  });

  final String code;
  final String name;
  final String? description;

  factory MerchantCategoryOption.fromJson(Map<String, dynamic> json) =>
      MerchantCategoryOption(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
      );
}

/// Kind of file a document slot accepts (drives picker options + S3 category).
enum DocumentMediaCategory { document, shopImage }

/// One uploadable verification document defined by the backend requirements
/// contract (`GET /shopkeeper/businesses/categories/{code}/requirements`).
class DocumentRequirement {
  const DocumentRequirement({
    required this.key,
    required this.label,
    this.hint,
    required this.required,
    required this.mediaCategory,
    this.icon,
  });

  /// Backend requirement code, e.g. `DRUG_LICENSE` (used as the document_type
  /// when attaching the file to the shop).
  final String key;
  final String label;
  final String? hint;
  final bool required;
  final DocumentMediaCategory mediaCategory;

  /// Material icon shown on the document card (fallback for generic slots).
  final IconData? icon;

  factory DocumentRequirement.fromJson(Map<String, dynamic> json) =>
      DocumentRequirement(
        key: json['doc_key'] as String? ?? '',
        label: json['label'] as String? ?? 'Document',
        hint: json['hint'] as String?,
        required: json['required'] as bool? ?? true,
        mediaCategory: (json['media_category'] as String? ?? 'DOCUMENT') ==
                'SHOP_IMAGE'
            ? DocumentMediaCategory.shopImage
            : DocumentMediaCategory.document,
      );
}

/// Documents + verification steps for a merchant category, as returned by the
/// backend category-requirements API. The wizard Documents step renders this —
/// never a hard-coded category→document table.
class CategoryRequirements {
  const CategoryRequirements({
    required this.categoryCode,
    required this.categoryName,
    required this.documents,
    this.requiresBankVerification = false,
    this.phoneOtpRequired = true,
    this.identityVerificationRequired = true,
    this.adminReviewRequired = true,
  });

  final String categoryCode;
  final String categoryName;

  /// Category-specific uploadable documents (e.g. Drug License, FSSAI…).
  final List<DocumentRequirement> documents;

  /// Whether the post-registration timeline includes bank verification.
  final bool requiresBankVerification;
  final bool phoneOtpRequired;
  final bool identityVerificationRequired;
  final bool adminReviewRequired;

  factory CategoryRequirements.fromJson(Map<String, dynamic> json) {
    final steps = json['steps'] as Map<String, dynamic>? ?? const {};
    return CategoryRequirements(
      categoryCode: json['category_code'] as String? ?? '',
      categoryName: json['category_name'] as String? ?? '',
      requiresBankVerification:
          json['requires_bank_verification'] as bool? ?? false,
      phoneOtpRequired: steps['phone_otp'] as bool? ?? true,
      identityVerificationRequired:
          steps['identity_verification'] as bool? ?? true,
      adminReviewRequired: steps['admin_review'] as bool? ?? true,
      documents: ((json['documents'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(DocumentRequirement.fromJson)
          .toList(growable: false),
    );
  }
}

/// Universal verification documents every business must supply. Category-
/// specific documents (Drug License, FSSAI, …) come from [CategoryRequirements]
/// and are rendered alongside these.
const kUniversalDocuments = <DocumentRequirement>[
  DocumentRequirement(
    key: 'GST_CERTIFICATE',
    label: 'GST Certificate',
    hint: 'Upload your GST registration certificate',
    required: false,
    mediaCategory: DocumentMediaCategory.document,
    icon: Icons.receipt_long_outlined,
  ),
  DocumentRequirement(
    key: 'SHOP_PHOTO',
    label: 'Shop Photo',
    hint: 'A clear photo of your shop front',
    required: false,
    mediaCategory: DocumentMediaCategory.shopImage,
    icon: Icons.storefront_outlined,
  ),
  DocumentRequirement(
    key: 'OWNER_ID_PROOF',
    label: 'Owner ID Proof',
    hint: 'Aadhaar / PAN / driving license of the owner',
    required: false,
    mediaCategory: DocumentMediaCategory.document,
    icon: Icons.badge_outlined,
  ),
  DocumentRequirement(
    key: 'OTHER_DOCUMENT',
    label: 'Other Documents',
    hint: 'Any additional document you want to attach',
    required: false,
    mediaCategory: DocumentMediaCategory.document,
    icon: Icons.upload_file_outlined,
  ),
];
