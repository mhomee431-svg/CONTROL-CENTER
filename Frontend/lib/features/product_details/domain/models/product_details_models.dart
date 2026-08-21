import 'package:freezed_annotation/freezed_annotation.dart';

part 'product_details_models.freezed.dart';
part 'product_details_models.g.dart';

@freezed
abstract class ShopOffer with _$ShopOffer {
  const factory ShopOffer({
    required String shopId,
    required String shopName,
    required String shopImageUrl,
    required double price,
    required double distanceInKm,
    required double rating,
    required bool isAvailable,
    required DateTime lastUpdated,
    String? offerText,
  }) = _ShopOffer;

  factory ShopOffer.fromJson(Map<String, dynamic> json) => _$ShopOfferFromJson(json);
}

@freezed
abstract class ProductDetails with _$ProductDetails {
  const factory ProductDetails({
    required String id,
    required String name,
    required String brand,
    required String category,
    required String description,
    required List<String> imageUrls,
    required String priceRange,
    required bool isAvailableAnywhere,
    required List<ShopOffer> nearbyShopsOffers,
    @Default(false) bool isSaved,
  }) = _ProductDetails;

  factory ProductDetails.fromJson(Map<String, dynamic> json) => _$ProductDetailsFromJson(json);
}