import 'package:freezed_annotation/freezed_annotation.dart';

part 'search_models.freezed.dart';
part 'search_models.g.dart';

@freezed
abstract class SearchSuggestion with _$SearchSuggestion {
  const factory SearchSuggestion({
    required String text,
    @Default(false) bool isCategory,
    @Default(false) bool isBrand,
  }) = _SearchSuggestion;

  factory SearchSuggestion.fromJson(Map<String, dynamic> json) =>
      _$SearchSuggestionFromJson(json);
}

/// Availability state of a shop's inventory for a product.
enum InventoryAvailability {
  inStock,
  outOfStock,
  lowStock,
  unknown,
}

/// How fresh the inventory signal is.
enum FreshnessLevel {
  fresh,
  recent,
  stale,
  unknown,
}

/// Sort options for search results.
enum SortOption {
  /// Nearest shops first (default).
  nearest,

  /// Lowest price first.
  lowestPrice,

  /// Highest rated shops first.
  highestRated,

  /// Most recently updated inventory first.
  recentlyUpdated,

  /// Backend relevance ranking.
  relevance,

  /// In-stock / purchasable results first.
  availability,
}

/// A single shop's offering of a product, returned by the search engine.
///
/// Answers: "Which nearby shop has this product, at what price, and how far?"
@freezed
abstract class ShopProductResult with _$ShopProductResult {
  const factory ShopProductResult({
    required String id,
    required String productId,
    required String productName,
    required String productImageUrl,
    required String shopId,
    required String shopName,
    required double price,
    required bool isAvailable,
    required double distanceInKm,
    required double shopRating,
    required DateTime lastUpdated,
    String? variant,
    double? mrp,
    String? shopImageUrl,
    String? offerText,
    String? shopAddress,
    double? shopLatitude,
    double? shopLongitude,
    String? category,
    String? brand,
    int? reviewCount,
    @Default(InventoryAvailability.unknown) InventoryAvailability availability,
    @Default(FreshnessLevel.unknown) FreshnessLevel freshness,
  }) = _ShopProductResult;

  const ShopProductResult._();

  factory ShopProductResult.fromJson(Map<String, dynamic> json) =>
      _$ShopProductResultFromJson(json);

  /// Purchasable only when backend explicitly reports in-stock AND fresh.
  bool get isPurchasableNow =>
      isAvailable &&
      availability == InventoryAvailability.inStock &&
      freshness != FreshnessLevel.stale &&
      freshness != FreshnessLevel.unknown;

  bool get isOutOfStock =>
      availability == InventoryAvailability.outOfStock || !isAvailable;

  bool get hasDiscount => mrp != null && mrp! > price;

  int get discountPercent {
    if (!hasDiscount) return 0;
    return ((mrp! - price) / mrp! * 100).round();
  }

  bool get hasCoordinates => shopLatitude != null && shopLongitude != null;
}