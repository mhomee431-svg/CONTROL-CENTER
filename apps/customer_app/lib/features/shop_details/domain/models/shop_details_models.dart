import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/catalog/business_capability.dart';

part 'shop_details_models.freezed.dart';
part 'shop_details_models.g.dart';

@freezed
abstract class ShopProductSummary with _$ShopProductSummary {
  const factory ShopProductSummary({
    required String productId,
    required String name,
    required String imageUrl,
    required double price,
    required bool isAvailable,
  }) = _ShopProductSummary;

  factory ShopProductSummary.fromJson(Map<String, dynamic> json) =>
      _$ShopProductSummaryFromJson(json);
}

@freezed
abstract class ShopProfile with _$ShopProfile {
  const factory ShopProfile({
    required String id,
    required String name,
    required String imageUrl,
    required double rating,
    required int reviewCount,
    required String address,
    required double distanceInKm,
    required String openingHours,
    required bool isOpenNow,
    required String phone,
    required String about,
    required DateTime lastInventoryUpdate,
    required List<String> activeOffers,
    required List<ShopProductSummary> availableProducts,
    @Default(false) bool isSaved,

    /// Categories the shop belongs to (e.g. "Electronics", "Mobile").
    @Default([]) List<String> categories,

    /// What this business may show a customer, as backend wire names
    /// (see `BusinessCapability`). Shipped on the shop payload so a restaurant
    /// or a service provider never inherits product-style price/stock UI —
    /// and so a category or a capability added later reaches customers without
    /// an app release.
    ///
    /// May be EMPTY when the payload predates capabilities (older backend, or
    /// served from the offline cache): [effectiveCapabilities] then resolves the
    /// compiled fallback instead of leaving the profile surface-less.
    @Default([]) List<String> capabilities,

    /// Canonical merchant-category NAME from the backend (e.g. "Restaurants",
    /// "Transport", "Personal Transport / Personal Travel"), or '' when absent.
    /// One input to the compiled fallback in [effectiveCapabilities].
    @Default('') String businessCategoryName,

    /// Canonical merchant-category CODE from the backend (e.g. "RESTAURANTS"),
    /// or '' when absent.
    @Default('') String businessCategoryCode,

    /// Free-form business type ("Retail", "Service", ...), or '' when absent.
    /// A "Service" type is the only signal a service business without a
    /// recognised category can give.
    @Default('') String businessType,

    /// Whether the shop is verified by the platform.
    @Default(false) bool isVerified,

    /// Shop latitude coordinate (0 = unavailable).
    @Default(0.0) double latitude,

    /// Shop longitude coordinate (0 = unavailable).
    @Default(0.0) double longitude,

    /// Secondary contact (e.g. WhatsApp) if available.
    @Default('') String secondaryPhone,

    /// Email contact if available.
    @Default('') String email,
  }) = _ShopProfile;

  const ShopProfile._();

  factory ShopProfile.fromJson(Map<String, dynamic> json) =>
      _$ShopProfileFromJson(json);

  /// What this business may show a customer — the answer the profile screen
  /// renders from.
  ///
  /// Resolution order is the contract (see [BusinessCapabilitySet.resolve]): the
  /// backend's wire list wins when present; otherwise `businessType`, then the
  /// compiled category table, then the product default. The screen therefore
  /// never has to guess whether this is a product shop, a restaurant or a
  /// service provider.
  BusinessCapabilitySet get effectiveCapabilities =>
      BusinessCapabilitySet.resolve(
        wire: capabilities,
        categoryName: businessCategoryName.isNotEmpty
            ? businessCategoryName
            : (categories.isNotEmpty ? categories.first : null),
        businessType: businessType.isNotEmpty ? businessType : null,
      );

  /// Whether the shop has usable coordinates for map/directions.
  bool get hasValidCoordinates =>
      latitude != 0 &&
      longitude != 0 &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}
