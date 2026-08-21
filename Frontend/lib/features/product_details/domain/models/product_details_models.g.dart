// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product_details_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ShopOffer _$ShopOfferFromJson(Map<String, dynamic> json) => _ShopOffer(
  shopId: json['shopId'] as String,
  shopName: json['shopName'] as String,
  shopImageUrl: json['shopImageUrl'] as String,
  price: (json['price'] as num).toDouble(),
  distanceInKm: (json['distanceInKm'] as num).toDouble(),
  rating: (json['rating'] as num).toDouble(),
  isAvailable: json['isAvailable'] as bool,
  lastUpdated: DateTime.parse(json['lastUpdated'] as String),
  offerText: json['offerText'] as String?,
);

Map<String, dynamic> _$ShopOfferToJson(_ShopOffer instance) =>
    <String, dynamic>{
      'shopId': instance.shopId,
      'shopName': instance.shopName,
      'shopImageUrl': instance.shopImageUrl,
      'price': instance.price,
      'distanceInKm': instance.distanceInKm,
      'rating': instance.rating,
      'isAvailable': instance.isAvailable,
      'lastUpdated': instance.lastUpdated.toIso8601String(),
      'offerText': instance.offerText,
    };

_ProductDetails _$ProductDetailsFromJson(Map<String, dynamic> json) =>
    _ProductDetails(
      id: json['id'] as String,
      name: json['name'] as String,
      brand: json['brand'] as String,
      category: json['category'] as String,
      description: json['description'] as String,
      imageUrls: (json['imageUrls'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      priceRange: json['priceRange'] as String,
      isAvailableAnywhere: json['isAvailableAnywhere'] as bool,
      nearbyShopsOffers: (json['nearbyShopsOffers'] as List<dynamic>)
          .map((e) => ShopOffer.fromJson(e as Map<String, dynamic>))
          .toList(),
      isSaved: json['isSaved'] as bool? ?? false,
    );

Map<String, dynamic> _$ProductDetailsToJson(_ProductDetails instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'brand': instance.brand,
      'category': instance.category,
      'description': instance.description,
      'imageUrls': instance.imageUrls,
      'priceRange': instance.priceRange,
      'isAvailableAnywhere': instance.isAvailableAnywhere,
      'nearbyShopsOffers': instance.nearbyShopsOffers,
      'isSaved': instance.isSaved,
    };
