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
    String? offerText,
  }) = _ShopProductResult;

  factory ShopProductResult.fromJson(Map<String, dynamic> json) =>
      _$ShopProductResultFromJson(json);
}

enum SortOption { nearest, lowestPrice, highestRated, recentlyUpdated }