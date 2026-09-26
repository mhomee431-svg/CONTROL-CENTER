import 'package:freezed_annotation/freezed_annotation.dart';

part 'product_details_models.freezed.dart';
part 'product_details_models.g.dart';

/// A single attribute of a product (e.g. Color: Red, Size: M).
@freezed
abstract class ProductAttribute with _$ProductAttribute {
  const factory ProductAttribute({
    required String name,
    required List<String> values,
  }) = _ProductAttribute;

  factory ProductAttribute.fromJson(Map<String, dynamic> json) =>
      _$ProductAttributeFromJson(json);
}

/// A product identifier (EAN, UPC, SKU, MPN, etc.).
@freezed
abstract class ProductIdentifier with _$ProductIdentifier {
  const factory ProductIdentifier({
    required String type,
    required String value,
    @Default(false) bool isPrimary,
  }) = _ProductIdentifier;

  factory ProductIdentifier.fromJson(Map<String, dynamic> json) =>
      _$ProductIdentifierFromJson(json);
}

/// A product variant (e.g. "128GB Black", "256GB Blue").
@freezed
abstract class ProductVariant with _$ProductVariant {
  const factory ProductVariant({
    required String id,
    required String name,
    String? sku,
    String? description,
    @Default(<String, String>{}) Map<String, String> attributes,
  }) = _ProductVariant;

  factory ProductVariant.fromJson(Map<String, dynamic> json) =>
      _$ProductVariantFromJson(json);
}

/// GLOBAL PRODUCT MASTER — the single source of truth for a product's
/// static information. This is NOT shop-specific.
@freezed
abstract class ProductMasterDetails with _$ProductMasterDetails {
  const factory ProductMasterDetails({
    required String id,
    required String name,
    required String brand,
    required String category,
    String? subcategory,
    String? description,
    String? shortDescription,
    String? baseUnit,
    double? baseQuantity,
    double? mrp,
    String? priceRange,
    @Default(<String>[]) List<String> imageUrls,
    @Default(<ProductVariant>[]) List<ProductVariant> variants,
    @Default(<ProductAttribute>[]) List<ProductAttribute> attributes,
    @Default(<ProductIdentifier>[]) List<ProductIdentifier> identifiers,
    @Default(false) bool isSaved,
  }) = _ProductMasterDetails;

  factory ProductMasterDetails.fromJson(Map<String, dynamic> json) =>
      _$ProductMasterDetailsFromJson(json);
}

/// SHOP-SPECIFIC INVENTORY — dynamic availability of a product at a
/// particular shop. This is NOT part of the global product master.
@freezed
abstract class ShopInventoryOffer with _$ShopInventoryOffer {
  const factory ShopInventoryOffer({
    required String shopId,
    required String shopName,
    required String shopImageUrl,
    required double price,
    double? mrp,
    required double distanceInKm,
    required double rating,
    required bool isAvailable,
    required DateTime lastUpdated,
    String? stockStatus,
    String? freshnessStatus,
    String? offerText,
  }) = _ShopInventoryOffer;

  factory ShopInventoryOffer.fromJson(Map<String, dynamic> json) =>
      _$ShopInventoryOfferFromJson(json);
}

/// Combined view for the Product Details screen.
/// Keeps [product] (global master) and [shopOffers] (shop inventory)
/// as separate, clearly-distinguished fields.
@freezed
abstract class ProductDetails with _$ProductDetails {
  const factory ProductDetails({
    required ProductMasterDetails product,
    @Default(<ShopInventoryOffer>[]) List<ShopInventoryOffer> shopOffers,
  }) = _ProductDetails;

  factory ProductDetails.fromJson(Map<String, dynamic> json) =>
      _$ProductDetailsFromJson(json);
}
