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

  factory ShopProductSummary.fromJson(Map<String, dynamic> json) => _$ShopProductSummaryFromJson(json);
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
  }) = _ShopProfile;

  factory ShopProfile.fromJson(Map<String, dynamic> json) => _$ShopProfileFromJson(json);
}