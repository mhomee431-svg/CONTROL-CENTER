import 'package:freezed_annotation/freezed_annotation.dart';

part 'home_data.freezed.dart';
part 'home_data.g.dart';

@freezed
abstract class Product with _$Product {
  const factory Product({
    required String id,
    required String name,
    required String brand,
    required String imageUrl,
    required String priceRange,
  }) = _Product;

  factory Product.fromJson(Map<String, dynamic> json) =>
      _$ProductFromJson(json);
}

@freezed
abstract class Shop with _$Shop {
  const factory Shop({
    required String id,
    required String name,
    required String imageUrl,
    required double distance,
    required double rating,
    required bool isVerified,

    /// The backend's opening-hours verdict for this shop.
    ///
    /// Nullable on purpose, and the null case is load-bearing: a payload that
    /// carries no verdict is NOT evidence that the shop is open. The card renders
    /// nothing for null rather than a reassuring "Open" it cannot back up (see
    /// [ShopOpenClosedBadge]).
    bool? isOpenNow,

    /// Whether the shop is taking orders right now. Null = not reported.
    bool? isAcceptingOrders,

    /// A one-line, context-specific figure for the card: a price range for a shop
    /// being browsed for a product, an availability count for a restaurant.
    ///
    /// Deliberately a preformatted STRING supplied by the caller that actually
    /// has the context. The card must not invent one, and a shop with no context
    /// shows no line at all rather than a hollow "N/A".
    String? contextLabel,
  }) = _Shop;

  factory Shop.fromJson(Map<String, dynamic> json) => _$ShopFromJson(json);
}

@freezed
abstract class Category with _$Category {
  const factory Category({
    required String id,
    required String name,
    required String iconUrl,
  }) = _Category;

  factory Category.fromJson(Map<String, dynamic> json) =>
      _$CategoryFromJson(json);
}

@freezed
abstract class Promotion with _$Promotion {
  const factory Promotion({
    required String id,
    required String title,
    required String subtitle,
    required String imageUrl,
    String? ctaLabel,
    String? ctaTarget,
  }) = _Promotion;

  factory Promotion.fromJson(Map<String, dynamic> json) =>
      _$PromotionFromJson(json);
}

@freezed
abstract class HomeData with _$HomeData {
  const factory HomeData({
    required List<Category> categories,
    required List<Product> popularProducts,
    required List<Shop> nearbyShops,
    required List<String> recentSearches,
    @Default([]) List<Product> recentlyViewed,
    @Default([]) List<Product> recommendedProducts,
    @Default([]) List<Promotion> promotions,
  }) = _HomeData;

  factory HomeData.fromJson(Map<String, dynamic> json) =>
      _$HomeDataFromJson(json);
}
