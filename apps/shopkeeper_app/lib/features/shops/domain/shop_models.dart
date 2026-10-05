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
    this.label,
    this.sortOrder = 0,
  });

  final String code;
  final String name;
  final String? description;

  /// The same text as [name], under the name the pickers and the dashboard
  /// label use. Two names for one string is redundant, but [name] is already
  /// part of the repository contract, so [label] is an alias rather than a
  /// second field that could disagree with it.
  final String? label;

  /// 1-based position in the offline fallback list; 0 for a category that came
  /// from the API without one.
  ///
  /// Dense and ordered on purpose: a sparse or duplicated order makes the
  /// picker ambiguous and can hide a newly inserted category.
  final int sortOrder;

  /// What to show: the explicit label when given, otherwise [name].
  String get displayLabel => label ?? name;

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

// ?? Capability model ????????????????????????????????????????????????????????
//
// Data-entry capabilities a business category can be granted, and the OFFLINE
// mirror of the backend registry. The backend is the authority; this table
// exists so a form renders before the network answers, not so the app can
// decide anything.
//
// Generated from `packages/api_contracts/category_capabilities.json`, which is
// exported from `backend/app/models/merchant_category.py`. `capability_contract_test.dart`
// reads that same file and fails if the two drift, so this table cannot quietly
// become a second source of truth.

/// What one category is allowed to do.
enum CategoryCapability {
  productCatalog('PRODUCT_CATALOG'),
  inventory('INVENTORY'),
  price('PRICE'),
  barcode('BARCODE'),
  offers('OFFERS'),
  operatingHours('OPERATING_HOURS'),
  services('SERVICES'),
  booking('BOOKING'),
  contact('CONTACT'),
  location('LOCATION'),
  import_('IMPORT'),
  pos('POS'),
  documents('DOCUMENTS'),
  categorySpecificData('CATEGORY_SPECIFIC_DATA'),
;
  const CategoryCapability(this.wire);

  /// The backend's wire value - what travels over HTTP.
  final String wire;

  /// Resolve a wire value, or null when this build does not know it.
  ///
  /// Null rather than a default: an unrecognised capability must be SKIPPED, not
  /// silently treated as granted, or the app renders a screen the server never
  /// authorised.
  static CategoryCapability? fromWire(String? value) {
    final key = (value ?? '').trim().toUpperCase();
    for (final capability in CategoryCapability.values) {
      if (capability.wire == key) return capability;
    }
    return null;
  }
}

/// Capabilities every business has, whatever its category: you can always be
/// contacted, and a shop that cannot state its location cannot be found. These
/// are re-applied AFTER narrowing, which is what makes narrowing safe.
const Set<CategoryCapability> kAlwaysPresentCapabilities = {
  CategoryCapability.contact,
  CategoryCapability.location,
};

/// Capabilities a SERVING business type does not have. A service shop has no
/// catalogue to fill, but still needs contact and location.
const Set<CategoryCapability> kServingOnlyExclusions = {
  CategoryCapability.barcode,
  CategoryCapability.import_,
  CategoryCapability.inventory,
  CategoryCapability.pos,
  CategoryCapability.productCatalog,
};

/// The five business types, in the order the wizard offers them.
///
/// Matched on EXACT text. A value outside this list narrows nothing, which is
/// indistinguishable from a genuine 'Service' - the defect this vocabulary
/// exists to prevent. `business_type_vocabulary_test` pins the spelling.
const List<String> kBusinessTypes = <String>[
  'Retail',
  'Wholesale',
  'Retail + Wholesale',
  'Service',
  'Other',
];

/// The same vocabulary under its capability-oriented name, so a consumer that
/// asks about business types and narrowing cannot pick up two lists.
const List<String> kBusinessTypesServerVocabulary = kBusinessTypes;

/// Offline capability table: category code -> what it may do.
///
/// The BASE set, before business-type narrowing and before the always-present
/// pair is re-applied - i.e. exactly what the backend exports per category.
const Map<String, Set<CategoryCapability>> kCategoryCapabilityDefaults =
    <String, Set<CategoryCapability>>{
  // Pharmacy & Healthcare
  'PHARMACY_HEALTHCARE': <CategoryCapability>{
    CategoryCapability.productCatalog,
    CategoryCapability.inventory,
    CategoryCapability.price,
    CategoryCapability.barcode,
    CategoryCapability.offers,
    CategoryCapability.operatingHours,
    CategoryCapability.import_,
    CategoryCapability.pos,
    CategoryCapability.documents,
  },
  // Beauty & Personal Care
  'BEAUTY_PERSONAL_CARE': <CategoryCapability>{
    CategoryCapability.productCatalog,
    CategoryCapability.inventory,
    CategoryCapability.price,
    CategoryCapability.barcode,
    CategoryCapability.offers,
    CategoryCapability.operatingHours,
    CategoryCapability.services,
    CategoryCapability.booking,
    CategoryCapability.import_,
    CategoryCapability.pos,
  },
  // Furniture & Home Care
  'FURNITURE_HOME_CARE': <CategoryCapability>{
    CategoryCapability.productCatalog,
    CategoryCapability.inventory,
    CategoryCapability.price,
    CategoryCapability.barcode,
    CategoryCapability.offers,
    CategoryCapability.operatingHours,
    CategoryCapability.services,
    CategoryCapability.import_,
  },
  // Household Goods
  'HOUSEHOLD_GOODS': <CategoryCapability>{
    CategoryCapability.productCatalog,
    CategoryCapability.inventory,
    CategoryCapability.price,
    CategoryCapability.barcode,
    CategoryCapability.offers,
    CategoryCapability.operatingHours,
    CategoryCapability.import_,
    CategoryCapability.pos,
  },
  // Sports, Fitness & Outdoor
  'SPORTS_FITNESS_OUTDOOR': <CategoryCapability>{
    CategoryCapability.productCatalog,
    CategoryCapability.inventory,
    CategoryCapability.price,
    CategoryCapability.barcode,
    CategoryCapability.offers,
    CategoryCapability.operatingHours,
    CategoryCapability.services,
    CategoryCapability.import_,
    CategoryCapability.pos,
  },
  // Books, Media & Stationery
  'BOOKS_MEDIA_STATIONERY': <CategoryCapability>{
    CategoryCapability.productCatalog,
    CategoryCapability.inventory,
    CategoryCapability.price,
    CategoryCapability.barcode,
    CategoryCapability.offers,
    CategoryCapability.operatingHours,
    CategoryCapability.import_,
    CategoryCapability.pos,
  },
  // Automotive Parts & Tools
  'AUTOMOTIVE_PARTS_TOOLS': <CategoryCapability>{
    CategoryCapability.productCatalog,
    CategoryCapability.inventory,
    CategoryCapability.price,
    CategoryCapability.barcode,
    CategoryCapability.offers,
    CategoryCapability.operatingHours,
    CategoryCapability.services,
    CategoryCapability.import_,
  },
  // Hardware
  'HARDWARE': <CategoryCapability>{
    CategoryCapability.productCatalog,
    CategoryCapability.inventory,
    CategoryCapability.price,
    CategoryCapability.barcode,
    CategoryCapability.offers,
    CategoryCapability.operatingHours,
    CategoryCapability.services,
    CategoryCapability.import_,
  },
  // Restaurants
  'RESTAURANTS': <CategoryCapability>{
    CategoryCapability.price,
    CategoryCapability.offers,
    CategoryCapability.operatingHours,
    CategoryCapability.services,
    CategoryCapability.booking,
    CategoryCapability.pos,
    CategoryCapability.documents,
    CategoryCapability.categorySpecificData,
  },
  // Transport
  'TRANSPORT': <CategoryCapability>{
    CategoryCapability.price,
    CategoryCapability.offers,
    CategoryCapability.operatingHours,
    CategoryCapability.services,
    CategoryCapability.booking,
    CategoryCapability.documents,
    CategoryCapability.categorySpecificData,
  },
  // Personal Transport / Personal Travel
  'PERSONAL_TRANSPORT_TRAVEL': <CategoryCapability>{
    CategoryCapability.offers,
    CategoryCapability.operatingHours,
    CategoryCapability.services,
    CategoryCapability.documents,
    CategoryCapability.categorySpecificData,
  },
};

/// The resolved answer for one category and business type.
class CategoryCapabilitySet {
  const CategoryCapabilitySet({
    required this.categoryCode,
    this.capabilities = const <CategoryCapability>{},
    this.businessType,
  });

  final String categoryCode;
  final String? businessType;
  final Set<CategoryCapability> capabilities;

  bool has(CategoryCapability capability) => capabilities.contains(capability);
  bool get isEmpty => capabilities.isEmpty;

  // Named gates rather than `has(CategoryCapability.x)` at every call site: a
  // route guard reading `!mayManageProducts` says what it is refusing, and a
  // capability can be re-pointed behind one name without touching its callers.
  bool get mayManageProducts => has(CategoryCapability.productCatalog);
  bool get mayManageInventory => has(CategoryCapability.inventory);
  bool get mayScanBarcodes => has(CategoryCapability.barcode);
  bool get mayImportInventory => has(CategoryCapability.import_);
  bool get mayUsePos => has(CategoryCapability.pos);
  bool get mayRunOffers => has(CategoryCapability.offers);
  bool get maySetOpeningHours => has(CategoryCapability.operatingHours);
  bool get mayPublishCatalog => has(CategoryCapability.productCatalog);
  bool get mayShowBooking => has(CategoryCapability.booking);
  bool get mayUploadDocuments => has(CategoryCapability.documents);

  /// Capability -> granted, for everything EXCEPT the always-present pair.
  ///
  /// CONTACT and LOCATION are excluded because they are not features - they are
  /// the floor every shop has. Leaving them in would make a route guard read
  /// `featureGates` as "this category does something", which is false for an
  /// unknown category that only ever yields the pair.
  Map<CategoryCapability, bool> get featureGates => <CategoryCapability, bool>{
        for (final capability in CategoryCapability.values)
          if (!kAlwaysPresentCapabilities.contains(capability))
            capability: capabilities.contains(capability),
      };

  /// Parse the server's answer.
  ///
  /// An unparseable payload yields an empty set rather than throwing: a shop
  /// whose capabilities could not be read gets an empty form and a retry, not
  /// a crash on the screen they opened to fix something else.
  factory CategoryCapabilitySet.fromJson(Map<String, dynamic> json) {
    final raw = json['capabilities'];
    final parsed = <CategoryCapability>{};
    if (raw is List) {
      for (final item in raw) {
        final capability = CategoryCapability.fromWire(item as String?);
        if (capability != null) parsed.add(capability);
      }
    }
    return CategoryCapabilitySet(
      categoryCode: '${json['category_code'] ?? ''}',
      businessType: json['business_type'] as String?,
      capabilities: parsed,
    );
  }
}

/// Resolve capabilities OFFLINE, exactly as the backend would.
///
/// Deliberately different from the backend in one place: the backend answers
/// 'unknown category' with nothing, because the caller turns that into a 404.
/// A client cannot - it must render SOMETHING, so it returns the minimum
/// (contact + location) rather than the full set. Granting capabilities a
/// server may not authorise is the worse failure: it fails at submit instead
/// of hiding a field the shopkeeper is entitled to.
///
/// An unknown or missing business type narrows NOTHING. Hiding a capability
/// wrongly locks a shop out of something they may have; showing one wrongly
/// surfaces the moment they submit, and says so.
CategoryCapabilitySet resolveCategoryCapabilities(
  String? categoryCode,
  String? businessType,
) {
  final code = (categoryCode ?? '').trim().toUpperCase();
  final base = kCategoryCapabilityDefaults[code] ?? kAlwaysPresentCapabilities;
  final type = (businessType ?? '').trim();
  final narrowed = type == 'Service'
      ? base.difference(kServingOnlyExclusions)
      : base;
  return CategoryCapabilitySet(
    categoryCode: code,
    businessType: type.isEmpty ? null : type,
    capabilities: {...narrowed, ...kAlwaysPresentCapabilities},
  );
}

/// The approved business categories, for the OFFLINE picker.
///
/// Same codes and names as the backend registry; `business_category_test`
/// reads that registry from disk and fails if this list drifts, so a screen
/// can never offer a category the server will reject at registration.
const List<MerchantCategoryOption> kBusinessCategoryFallback =
    <MerchantCategoryOption>[
  MerchantCategoryOption(
    code: 'PHARMACY_HEALTHCARE',
    label: 'Pharmacy & Healthcare',
    name: 'Pharmacy & Healthcare',
    sortOrder: 1,
  ),
  MerchantCategoryOption(
    code: 'BEAUTY_PERSONAL_CARE',
    label: 'Beauty & Personal Care',
    name: 'Beauty & Personal Care',
    sortOrder: 2,
  ),
  MerchantCategoryOption(
    code: 'FURNITURE_HOME_CARE',
    label: 'Furniture & Home Care',
    name: 'Furniture & Home Care',
    sortOrder: 3,
  ),
  MerchantCategoryOption(
    code: 'HOUSEHOLD_GOODS',
    label: 'Household Goods',
    name: 'Household Goods',
    sortOrder: 4,
  ),
  MerchantCategoryOption(
    code: 'SPORTS_FITNESS_OUTDOOR',
    label: 'Sports, Fitness & Outdoor',
    name: 'Sports, Fitness & Outdoor',
    sortOrder: 5,
  ),
  MerchantCategoryOption(
    code: 'BOOKS_MEDIA_STATIONERY',
    label: 'Books, Media & Stationery',
    name: 'Books, Media & Stationery',
    sortOrder: 6,
  ),
  MerchantCategoryOption(
    code: 'AUTOMOTIVE_PARTS_TOOLS',
    label: 'Automotive Parts & Tools',
    name: 'Automotive Parts & Tools',
    sortOrder: 7,
  ),
  MerchantCategoryOption(
    code: 'HARDWARE',
    label: 'Hardware',
    name: 'Hardware',
    sortOrder: 8,
  ),
  MerchantCategoryOption(
    code: 'RESTAURANTS',
    label: 'Restaurants',
    name: 'Restaurants',
    sortOrder: 9,
  ),
  MerchantCategoryOption(
    code: 'TRANSPORT',
    label: 'Transport',
    name: 'Transport',
    sortOrder: 10,
  ),
  MerchantCategoryOption(
    code: 'PERSONAL_TRANSPORT_TRAVEL',
    label: 'Personal Transport / Personal Travel',
    name: 'Personal Transport / Personal Travel',
    sortOrder: 11,
  ),
];

/// The canonical display name for a category code.
///
/// Reads the offline table so the ampersand the backend prints survives
/// ('Pharmacy & Healthcare', not the 'Pharmacy healthcare' a humanise-only
/// helper would produce). An unknown code is humanised rather than dropped,
/// so a category the server adds early still reads sensibly.
String businessCategoryLabel(String? code) {
  final key = (code ?? '').trim().toUpperCase();
  if (key.isEmpty) return 'Not set';
  for (final category in kBusinessCategoryFallback) {
    if (category.code == key) return category.displayLabel;
  }
  final words = key.toLowerCase().replaceAll('_', ' ').trim();
  if (words.isEmpty) return 'Not set';
  return words[0].toUpperCase() + words.substring(1);
}

/// Trades that publish data of their OWN once `CATEGORY_SPECIFIC_DATA` is granted.
///
/// `CATEGORY_SPECIFIC_DATA` says "this trade has data of its own" but not WHICH,
/// and the answer is genuinely different per trade: a tour operator has a
/// service area and a package, a restaurant has a menu. Without this axis every
/// category with that capability would render the same fields, and two thirds of
/// them would be wrong.
///
/// Mirrors the backend's `SERVICE_PROFILE_FIELDS` keys. A category with no entry
/// simply has no profile, which means no category-specific fields.
enum ServiceCategoryProfile {
  personalTravel('PERSONAL_TRANSPORT_TRAVEL'),
  transport('TRANSPORT'),
  restaurant('RESTAURANTS');

  const ServiceCategoryProfile(this.wire);

  /// The backend's category code for this profile.
  final String wire;

  static ServiceCategoryProfile? fromWire(String? value) {
    final key = (value ?? '').trim().toUpperCase();
    for (final profile in ServiceCategoryProfile.values) {
      if (profile.wire == key) return profile;
    }
    return null;
  }
}

/// The service profile a category belongs to, or null when it has none.
ServiceCategoryProfile? serviceProfileForCategory(String? categoryCode) =>
    ServiceCategoryProfile.fromWire((categoryCode ?? '').trim().toUpperCase());
