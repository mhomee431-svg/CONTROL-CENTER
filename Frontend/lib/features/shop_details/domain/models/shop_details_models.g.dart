// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shop_details_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ShopProductSummary _$ShopProductSummaryFromJson(Map<String, dynamic> json) =>
    _ShopProductSummary(
      productId: json['productId'] as String,
      name: json['name'] as String,
      imageUrl: json['imageUrl'] as String,
      price: (json['price'] as num).toDouble(),
      isAvailable: json['isAvailable'] as bool,
    );

Map<String, dynamic> _$ShopProductSummaryToJson(_ShopProductSummary instance) =>
    <String, dynamic>{
      'productId': instance.productId,
      'name': instance.name,
      'imageUrl': instance.imageUrl,
      'price': instance.price,
      'isAvailable': instance.isAvailable,
    };

_ShopProfile _$ShopProfileFromJson(Map<String, dynamic> json) => _ShopProfile(
  id: json['id'] as String,
  name: json['name'] as String,
  imageUrl: json['imageUrl'] as String,
  rating: (json['rating'] as num).toDouble(),
  reviewCount: (json['reviewCount'] as num).toInt(),
  address: json['address'] as String,
  distanceInKm: (json['distanceInKm'] as num).toDouble(),
  openingHours: json['openingHours'] as String,
  isOpenNow: json['isOpenNow'] as bool,
  phone: json['phone'] as String,
  about: json['about'] as String,
  lastInventoryUpdate: DateTime.parse(json['lastInventoryUpdate'] as String),
  activeOffers: (json['activeOffers'] as List<dynamic>)
      .map((e) => e as String)
      .toList(),
  availableProducts: (json['availableProducts'] as List<dynamic>)
      .map((e) => ShopProductSummary.fromJson(e as Map<String, dynamic>))
      .toList(),
  isSaved: json['isSaved'] as bool? ?? false,
);

Map<String, dynamic> _$ShopProfileToJson(_ShopProfile instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'imageUrl': instance.imageUrl,
      'rating': instance.rating,
      'reviewCount': instance.reviewCount,
      'address': instance.address,
      'distanceInKm': instance.distanceInKm,
      'openingHours': instance.openingHours,
      'isOpenNow': instance.isOpenNow,
      'phone': instance.phone,
      'about': instance.about,
      'lastInventoryUpdate': instance.lastInventoryUpdate.toIso8601String(),
      'activeOffers': instance.activeOffers,
      'availableProducts': instance.availableProducts,
      'isSaved': instance.isSaved,
    };
