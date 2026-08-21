// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'home_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Product _$ProductFromJson(Map<String, dynamic> json) => _Product(
  id: json['id'] as String,
  name: json['name'] as String,
  brand: json['brand'] as String,
  imageUrl: json['imageUrl'] as String,
  priceRange: json['priceRange'] as String,
);

Map<String, dynamic> _$ProductToJson(_Product instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'brand': instance.brand,
  'imageUrl': instance.imageUrl,
  'priceRange': instance.priceRange,
};

_Shop _$ShopFromJson(Map<String, dynamic> json) => _Shop(
  id: json['id'] as String,
  name: json['name'] as String,
  imageUrl: json['imageUrl'] as String,
  distance: (json['distance'] as num).toDouble(),
  rating: (json['rating'] as num).toDouble(),
  isVerified: json['isVerified'] as bool,
);

Map<String, dynamic> _$ShopToJson(_Shop instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'imageUrl': instance.imageUrl,
  'distance': instance.distance,
  'rating': instance.rating,
  'isVerified': instance.isVerified,
};

_Category _$CategoryFromJson(Map<String, dynamic> json) => _Category(
  id: json['id'] as String,
  name: json['name'] as String,
  iconUrl: json['iconUrl'] as String,
);

Map<String, dynamic> _$CategoryToJson(_Category instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'iconUrl': instance.iconUrl,
};

_HomeData _$HomeDataFromJson(Map<String, dynamic> json) => _HomeData(
  categories: (json['categories'] as List<dynamic>)
      .map((e) => Category.fromJson(e as Map<String, dynamic>))
      .toList(),
  popularProducts: (json['popularProducts'] as List<dynamic>)
      .map((e) => Product.fromJson(e as Map<String, dynamic>))
      .toList(),
  nearbyShops: (json['nearbyShops'] as List<dynamic>)
      .map((e) => Shop.fromJson(e as Map<String, dynamic>))
      .toList(),
  recentSearches: (json['recentSearches'] as List<dynamic>)
      .map((e) => e as String)
      .toList(),
);

Map<String, dynamic> _$HomeDataToJson(_HomeData instance) => <String, dynamic>{
  'categories': instance.categories,
  'popularProducts': instance.popularProducts,
  'nearbyShops': instance.nearbyShops,
  'recentSearches': instance.recentSearches,
};
