import 'package:flutter/material.dart';

import '../../auth/domain/auth_models.dart';

export '../../auth/domain/auth_models.dart' show ShopSummary;

/// Verification lifecycle for a shop
/// (PENDING → SUBMITTED → UNDER_REVIEW → VERIFIED / REJECTED / EXPIRED).

class VerificationInfo {
  const VerificationInfo({required this.status, this.reviewNotes});

  final String status;
  final String? reviewNotes;

  bool get isVerified => status == 'VERIFIED';
  bool get isRejected => status == 'REJECTED';
  bool get isPending => !isVerified && !isRejected;

  factory VerificationInfo.fromJson(Map<String, dynamic>? json) =>
      VerificationInfo(
        status: (json?['status'] as String?) ?? 'PENDING',
        reviewNotes: json?['review_notes'] as String?,
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
      );
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
