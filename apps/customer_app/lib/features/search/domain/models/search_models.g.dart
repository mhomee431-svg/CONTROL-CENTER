// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SearchSuggestion _$SearchSuggestionFromJson(Map<String, dynamic> json) =>
    _SearchSuggestion(
      text: json['text'] as String,
      isCategory: json['isCategory'] as bool? ?? false,
      isBrand: json['isBrand'] as bool? ?? false,
    );

Map<String, dynamic> _$SearchSuggestionToJson(_SearchSuggestion instance) =>
    <String, dynamic>{
      'text': instance.text,
      'isCategory': instance.isCategory,
      'isBrand': instance.isBrand,
    };

_ShopProductResult _$ShopProductResultFromJson(Map<String, dynamic> json) =>
    _ShopProductResult(
      id: json['id'] as String,
      productId: json['productId'] as String,
      productName: json['productName'] as String,
      productImageUrl: json['productImageUrl'] as String,
      shopId: json['shopId'] as String,
      shopName: json['shopName'] as String,
      price: (json['price'] as num).toDouble(),
      isAvailable: json['isAvailable'] as bool,
      distanceInKm: (json['distanceInKm'] as num).toDouble(),
      shopRating: (json['shopRating'] as num).toDouble(),
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
      variant: json['variant'] as String?,
      mrp: (json['mrp'] as num?)?.toDouble(),
      shopImageUrl: json['shopImageUrl'] as String?,
      offerText: json['offerText'] as String?,
      shopAddress: json['shopAddress'] as String?,
      shopLatitude: (json['shopLatitude'] as num?)?.toDouble(),
      shopLongitude: (json['shopLongitude'] as num?)?.toDouble(),
      category: json['category'] as String?,
      brand: json['brand'] as String?,
      reviewCount: (json['reviewCount'] as num?)?.toInt(),
      isOpenNow: json['isOpenNow'] as bool?,
      isAcceptingOrders: json['isAcceptingOrders'] as bool?,
      availability:
          $enumDecodeNullable(
            _$InventoryAvailabilityEnumMap,
            json['availability'],
          ) ??
          InventoryAvailability.unknown,
      freshness:
          $enumDecodeNullable(_$FreshnessLevelEnumMap, json['freshness']) ??
          FreshnessLevel.unknown,
      freshnessStatusRaw: json['freshnessStatusRaw'] as String?,
    );

Map<String, dynamic> _$ShopProductResultToJson(_ShopProductResult instance) =>
    <String, dynamic>{
      'id': instance.id,
      'productId': instance.productId,
      'productName': instance.productName,
      'productImageUrl': instance.productImageUrl,
      'shopId': instance.shopId,
      'shopName': instance.shopName,
      'price': instance.price,
      'isAvailable': instance.isAvailable,
      'distanceInKm': instance.distanceInKm,
      'shopRating': instance.shopRating,
      'lastUpdated': instance.lastUpdated.toIso8601String(),
      'variant': instance.variant,
      'mrp': instance.mrp,
      'shopImageUrl': instance.shopImageUrl,
      'offerText': instance.offerText,
      'shopAddress': instance.shopAddress,
      'shopLatitude': instance.shopLatitude,
      'shopLongitude': instance.shopLongitude,
      'category': instance.category,
      'brand': instance.brand,
      'reviewCount': instance.reviewCount,
      'isOpenNow': instance.isOpenNow,
      'isAcceptingOrders': instance.isAcceptingOrders,
      'availability': _$InventoryAvailabilityEnumMap[instance.availability]!,
      'freshness': _$FreshnessLevelEnumMap[instance.freshness]!,
      'freshnessStatusRaw': instance.freshnessStatusRaw,
    };

const _$InventoryAvailabilityEnumMap = {
  InventoryAvailability.inStock: 'inStock',
  InventoryAvailability.outOfStock: 'outOfStock',
  InventoryAvailability.lowStock: 'lowStock',
  InventoryAvailability.unknown: 'unknown',
};

const _$FreshnessLevelEnumMap = {
  FreshnessLevel.fresh: 'fresh',
  FreshnessLevel.recent: 'recent',
  FreshnessLevel.stale: 'stale',
  FreshnessLevel.unknown: 'unknown',
};
