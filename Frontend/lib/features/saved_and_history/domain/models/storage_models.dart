import 'package:freezed_annotation/freezed_annotation.dart';

part 'storage_models.freezed.dart';
part 'storage_models.g.dart';

@freezed
abstract class SavedProductItem with _$SavedProductItem {
  const factory SavedProductItem({
    required String productId,
    required String name,
    required String brand,
    required double lowestPrice,
    required String imageUrl,
    required DateTime savedAt,
    @Default(false) bool isSynced,
  }) = _SavedProductItem;

  factory SavedProductItem.fromJson(Map<String, dynamic> json) =>
      _$SavedProductItemFromJson(json);
}

@freezed
abstract class SavedShopItem with _$SavedShopItem {
  const factory SavedShopItem({
    required String shopId,
    required String name,
    required String address,
    required String imageUrl,
    required double rating,
    required DateTime savedAt,
    @Default(false) bool isSynced,
  }) = _SavedShopItem;

  factory SavedShopItem.fromJson(Map<String, dynamic> json) =>
      _$SavedShopItemFromJson(json);
}

@freezed
abstract class RecentlyViewedItem with _$RecentlyViewedItem {
  const factory RecentlyViewedItem({
    required String productId,
    required String name,
    required String imageUrl,
    required double price,
    required DateTime viewedAt,
  }) = _RecentlyViewedItem;

  factory RecentlyViewedItem.fromJson(Map<String, dynamic> json) =>
      _$RecentlyViewedItemFromJson(json);
}

@freezed
abstract class RecentSearchItem with _$RecentSearchItem {
  const factory RecentSearchItem({
    required String query,
    required DateTime searchedAt,
  }) = _RecentSearchItem;

  factory RecentSearchItem.fromJson(Map<String, dynamic> json) =>
      _$RecentSearchItemFromJson(json);
}