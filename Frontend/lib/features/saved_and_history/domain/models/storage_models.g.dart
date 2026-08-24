// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'storage_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SavedProductItem _$SavedProductItemFromJson(Map<String, dynamic> json) =>
    _SavedProductItem(
      productId: json['productId'] as String,
      name: json['name'] as String,
      brand: json['brand'] as String,
      lowestPrice: (json['lowestPrice'] as num).toDouble(),
      imageUrl: json['imageUrl'] as String,
      savedAt: DateTime.parse(json['savedAt'] as String),
      isSynced: json['isSynced'] as bool? ?? false,
    );

Map<String, dynamic> _$SavedProductItemToJson(_SavedProductItem instance) =>
    <String, dynamic>{
      'productId': instance.productId,
      'name': instance.name,
      'brand': instance.brand,
      'lowestPrice': instance.lowestPrice,
      'imageUrl': instance.imageUrl,
      'savedAt': instance.savedAt.toIso8601String(),
      'isSynced': instance.isSynced,
    };

_SavedShopItem _$SavedShopItemFromJson(Map<String, dynamic> json) =>
    _SavedShopItem(
      shopId: json['shopId'] as String,
      name: json['name'] as String,
      address: json['address'] as String,
      imageUrl: json['imageUrl'] as String,
      rating: (json['rating'] as num).toDouble(),
      savedAt: DateTime.parse(json['savedAt'] as String),
      isSynced: json['isSynced'] as bool? ?? false,
    );

Map<String, dynamic> _$SavedShopItemToJson(_SavedShopItem instance) =>
    <String, dynamic>{
      'shopId': instance.shopId,
      'name': instance.name,
      'address': instance.address,
      'imageUrl': instance.imageUrl,
      'rating': instance.rating,
      'savedAt': instance.savedAt.toIso8601String(),
      'isSynced': instance.isSynced,
    };

_RecentlyViewedItem _$RecentlyViewedItemFromJson(Map<String, dynamic> json) =>
    _RecentlyViewedItem(
      productId: json['productId'] as String,
      name: json['name'] as String,
      imageUrl: json['imageUrl'] as String,
      price: (json['price'] as num).toDouble(),
      viewedAt: DateTime.parse(json['viewedAt'] as String),
    );

Map<String, dynamic> _$RecentlyViewedItemToJson(_RecentlyViewedItem instance) =>
    <String, dynamic>{
      'productId': instance.productId,
      'name': instance.name,
      'imageUrl': instance.imageUrl,
      'price': instance.price,
      'viewedAt': instance.viewedAt.toIso8601String(),
    };

_RecentlyViewedShopItem _$RecentlyViewedShopItemFromJson(
  Map<String, dynamic> json,
) => _RecentlyViewedShopItem(
  shopId: json['shopId'] as String,
  name: json['name'] as String,
  address: json['address'] as String,
  imageUrl: json['imageUrl'] as String,
  rating: (json['rating'] as num).toDouble(),
  viewedAt: DateTime.parse(json['viewedAt'] as String),
);

Map<String, dynamic> _$RecentlyViewedShopItemToJson(
  _RecentlyViewedShopItem instance,
) => <String, dynamic>{
  'shopId': instance.shopId,
  'name': instance.name,
  'address': instance.address,
  'imageUrl': instance.imageUrl,
  'rating': instance.rating,
  'viewedAt': instance.viewedAt.toIso8601String(),
};

_RecentSearchItem _$RecentSearchItemFromJson(Map<String, dynamic> json) =>
    _RecentSearchItem(
      query: json['query'] as String,
      searchedAt: DateTime.parse(json['searchedAt'] as String),
    );

Map<String, dynamic> _$RecentSearchItemToJson(_RecentSearchItem instance) =>
    <String, dynamic>{
      'query': instance.query,
      'searchedAt': instance.searchedAt.toIso8601String(),
    };
