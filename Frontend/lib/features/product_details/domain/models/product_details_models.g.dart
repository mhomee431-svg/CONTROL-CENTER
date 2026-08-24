// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product_details_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ProductAttribute _$ProductAttributeFromJson(Map<String, dynamic> json) =>
    _ProductAttribute(
      name: json['name'] as String,
      values: (json['values'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$ProductAttributeToJson(_ProductAttribute instance) =>
    <String, dynamic>{'name': instance.name, 'values': instance.values};

_ProductIdentifier _$ProductIdentifierFromJson(Map<String, dynamic> json) =>
    _ProductIdentifier(
      type: json['type'] as String,
      value: json['value'] as String,
      isPrimary: json['isPrimary'] as bool? ?? false,
    );

Map<String, dynamic> _$ProductIdentifierToJson(_ProductIdentifier instance) =>
    <String, dynamic>{
      'type': instance.type,
      'value': instance.value,
      'isPrimary': instance.isPrimary,
    };

_ProductVariant _$ProductVariantFromJson(Map<String, dynamic> json) =>
    _ProductVariant(
      id: json['id'] as String,
      name: json['name'] as String,
      sku: json['sku'] as String?,
      description: json['description'] as String?,
      attributes:
          (json['attributes'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, e as String),
          ) ??
          const <String, String>{},
    );

Map<String, dynamic> _$ProductVariantToJson(_ProductVariant instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'sku': instance.sku,
      'description': instance.description,
      'attributes': instance.attributes,
    };

_ProductMasterDetails _$ProductMasterDetailsFromJson(
  Map<String, dynamic> json,
) => _ProductMasterDetails(
  id: json['id'] as String,
  name: json['name'] as String,
  brand: json['brand'] as String,
  category: json['category'] as String,
  subcategory: json['subcategory'] as String?,
  description: json['description'] as String?,
  shortDescription: json['shortDescription'] as String?,
  baseUnit: json['baseUnit'] as String?,
  baseQuantity: (json['baseQuantity'] as num?)?.toDouble(),
  mrp: (json['mrp'] as num?)?.toDouble(),
  priceRange: json['priceRange'] as String?,
  imageUrls:
      (json['imageUrls'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const <String>[],
  variants:
      (json['variants'] as List<dynamic>?)
          ?.map((e) => ProductVariant.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <ProductVariant>[],
  attributes:
      (json['attributes'] as List<dynamic>?)
          ?.map((e) => ProductAttribute.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <ProductAttribute>[],
  identifiers:
      (json['identifiers'] as List<dynamic>?)
          ?.map((e) => ProductIdentifier.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <ProductIdentifier>[],
  isSaved: json['isSaved'] as bool? ?? false,
);

Map<String, dynamic> _$ProductMasterDetailsToJson(
  _ProductMasterDetails instance,
) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'brand': instance.brand,
  'category': instance.category,
  'subcategory': instance.subcategory,
  'description': instance.description,
  'shortDescription': instance.shortDescription,
  'baseUnit': instance.baseUnit,
  'baseQuantity': instance.baseQuantity,
  'mrp': instance.mrp,
  'priceRange': instance.priceRange,
  'imageUrls': instance.imageUrls,
  'variants': instance.variants,
  'attributes': instance.attributes,
  'identifiers': instance.identifiers,
  'isSaved': instance.isSaved,
};

_ShopInventoryOffer _$ShopInventoryOfferFromJson(Map<String, dynamic> json) =>
    _ShopInventoryOffer(
      shopId: json['shopId'] as String,
      shopName: json['shopName'] as String,
      shopImageUrl: json['shopImageUrl'] as String,
      price: (json['price'] as num).toDouble(),
      mrp: (json['mrp'] as num?)?.toDouble(),
      distanceInKm: (json['distanceInKm'] as num).toDouble(),
      rating: (json['rating'] as num).toDouble(),
      isAvailable: json['isAvailable'] as bool,
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
      stockStatus: json['stockStatus'] as String?,
      freshnessStatus: json['freshnessStatus'] as String?,
      offerText: json['offerText'] as String?,
    );

Map<String, dynamic> _$ShopInventoryOfferToJson(_ShopInventoryOffer instance) =>
    <String, dynamic>{
      'shopId': instance.shopId,
      'shopName': instance.shopName,
      'shopImageUrl': instance.shopImageUrl,
      'price': instance.price,
      'mrp': instance.mrp,
      'distanceInKm': instance.distanceInKm,
      'rating': instance.rating,
      'isAvailable': instance.isAvailable,
      'lastUpdated': instance.lastUpdated.toIso8601String(),
      'stockStatus': instance.stockStatus,
      'freshnessStatus': instance.freshnessStatus,
      'offerText': instance.offerText,
    };

_ProductDetails _$ProductDetailsFromJson(Map<String, dynamic> json) =>
    _ProductDetails(
      product: ProductMasterDetails.fromJson(
        json['product'] as Map<String, dynamic>,
      ),
      shopOffers:
          (json['shopOffers'] as List<dynamic>?)
              ?.map(
                (e) => ShopInventoryOffer.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const <ShopInventoryOffer>[],
    );

Map<String, dynamic> _$ProductDetailsToJson(_ProductDetails instance) =>
    <String, dynamic>{
      'product': instance.product,
      'shopOffers': instance.shopOffers,
    };
