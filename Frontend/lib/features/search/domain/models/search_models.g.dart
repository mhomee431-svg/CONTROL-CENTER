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
      offerText: json['offerText'] as String?,
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
      'offerText': instance.offerText,
    };
