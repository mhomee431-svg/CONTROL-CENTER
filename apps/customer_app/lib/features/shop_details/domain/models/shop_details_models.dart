import 'package:freezed_annotation/freezed_annotation.dart';

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

  /// Whether the shop has usable coordinates for map/directions.
  bool get hasValidCoordinates =>
      latitude != 0 &&
      longitude != 0 &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}
