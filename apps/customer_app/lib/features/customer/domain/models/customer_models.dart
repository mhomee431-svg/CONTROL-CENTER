import '../../../../core/network/json_map.dart';

/// Domain models for customer features (favourites, recently viewed, share).
///
/// Plain Dart classes — no code generation required so they work standalone.

/// Every field these models know how to read.
///
/// Passed to [JsonMap.unknownKeys] so a field the server adds or renames is
/// VISIBLE in a debug build instead of silently disappearing. The cost is one
/// line per model; the benefit is that a contract change is noticed in
/// development rather than by a customer.
const _favoriteKeys = {
  'id',
  'item_type',
  'item_id',
  'metadata_json',
  'created_at',
  'item',
};
const _favouriteItemKeys = {'id', 'name', 'slug', 'image_url'};
const _recentProductKeys = {
  'product_master_id',
  'name',
  'slug',
  'image_url',
  'variant_id',
  'shop_product_id',
  'view_count',
  'last_viewed_at',
};
const _sharePayloadKeys = {
  'product_master_id',
  'name',
  'slug',
  'description',
  'image_url',
  'shop_count',
  'price_range',
  'currency',
};
const _priceRangeKeys = {'min', 'max'};

/// A customer's favourite item (polymorphic: product/shop/brand/category).
class CustomerFavorite {
  final int id;
  final String itemType;
  final int itemId;
  final Map<String, dynamic>? metadataJson;
  final String? createdAt;
  final FavouriteItem? item;

  const CustomerFavorite({
    required this.id,
    required this.itemType,
    required this.itemId,
    this.metadataJson,
    this.createdAt,
    this.item,
  });

  factory CustomerFavorite.fromJson(Map<String, dynamic> json) {
    final map = JsonMap.tryParse(json);
    assert(
      map.unknownKeys(_favoriteKeys).isEmpty,
      'CustomerFavorite: unrecognised fields '
      '${map.unknownKeys(_favoriteKeys)}',
    );

    return CustomerFavorite(
      // `id` used to be read as `json['id'] as int`, which threw outright when
      // the field was absent — taking the whole favourites screen down over a
      // missing id.
      id: map.integerOr('id'),
      // `item_type` is an open vocabulary the backend keeps extending, so the
      // raw string is kept rather than mapped to a closed enum that would need
      // a code change per new type.
      itemType: map.stringOr('item_type'),
      itemId: map.integerOr('item_id'),
      metadataJson: map.raw['metadata_json'] is Map
          ? Map<String, dynamic>.from(map.raw['metadata_json'] as Map)
          : null,
      createdAt: map.string('created_at'),
      // A missing or non-object `item` is normal (the target may have been
      // deleted), so it decodes to null rather than throwing. The type check
      // matters: `has()` is true for a non-null string too, and decoding a
      // bare string would fabricate an empty FavouriteItem rather than admit
      // there is nothing to show.
      item: map.raw['item'] is Map
          ? FavouriteItem.fromJson(map.raw['item'])
          : null,
    );
  }
}

/// Resolved snapshot of the favourited item.
class FavouriteItem {
  final int id;
  final String name;
  final String? slug;
  final String? imageUrl;

  const FavouriteItem({
    required this.id,
    required this.name,
    this.slug,
    this.imageUrl,
  });

  factory FavouriteItem.fromJson(Object? value) {
    final map = value is JsonMap ? value : JsonMap.tryParse(value);
    assert(
      map.unknownKeys(_favouriteItemKeys).isEmpty,
      'FavouriteItem: unrecognised fields '
      '${map.unknownKeys(_favouriteItemKeys)}',
    );

    return FavouriteItem(
      id: map.integerOr('id'),
      name: map.stringOr('name'),
      slug: map.string('slug'),
      imageUrl: map.string('image_url'),
    );
  }
}

/// A product the customer recently viewed.
class RecentProduct {
  final int productMasterId;
  final String name;
  final String? slug;
  final String? imageUrl;
  final int? variantId;
  final int? shopProductId;
  final int? viewCount;
  final String? lastViewedAt;

  const RecentProduct({
    required this.productMasterId,
    required this.name,
    this.slug,
    this.imageUrl,
    this.variantId,
    this.shopProductId,
    this.viewCount,
    this.lastViewedAt,
  });

  factory RecentProduct.fromJson(Map<String, dynamic> json) {
    final map = JsonMap.tryParse(json);
    assert(
      map.unknownKeys(_recentProductKeys).isEmpty,
      'RecentProduct: unrecognised fields '
      '${map.unknownKeys(_recentProductKeys)}',
    );

    return RecentProduct(
      productMasterId: map.integerOr('product_master_id'),
      name: map.stringOr('name'),
      slug: map.string('slug'),
      imageUrl: map.string('image_url'),
      variantId: map.integer('variant_id'),
      shopProductId: map.integer('shop_product_id'),
      // `view_count` is genuinely optional — a product seen for the first time
      // may not have a count yet — so null is preserved rather than faked as 0.
      viewCount: map.integer('view_count'),
      lastViewedAt: map.string('last_viewed_at'),
    );
  }
}

/// Share payload for a product (live price range + shop count).
class ProductSharePayload {
  final int productMasterId;
  final String name;
  final String? slug;
  final String? description;
  final String? imageUrl;
  final int? shopCount;
  final PriceRange? priceRange;
  final String? currency;

  const ProductSharePayload({
    required this.productMasterId,
    required this.name,
    this.slug,
    this.description,
    this.imageUrl,
    this.shopCount,
    this.priceRange,
    this.currency,
  });

  factory ProductSharePayload.fromJson(Map<String, dynamic> json) {
    final map = JsonMap.tryParse(json);
    assert(
      map.unknownKeys(_sharePayloadKeys).isEmpty,
      'ProductSharePayload: unrecognised fields '
      '${map.unknownKeys(_sharePayloadKeys)}',
    );

    return ProductSharePayload(
      productMasterId: map.integerOr('product_master_id'),
      name: map.stringOr('name'),
      slug: map.string('slug'),
      description: map.string('description'),
      imageUrl: map.string('image_url'),
      shopCount: map.integer('shop_count'),
      // A share payload for a product with no live offers has no range; null
      // keeps "unknown" distinct from "0 to 0".
      priceRange: map.has('price_range')
          ? PriceRange.fromJson(map.raw['price_range'])
          : null,
      currency: map.string('currency'),
    );
  }
}

class PriceRange {
  final double min;
  final double max;

  const PriceRange({required this.min, required this.max});

  factory PriceRange.fromJson(Object? value) {
    final map = value is JsonMap ? value : JsonMap.tryParse(value);
    assert(
      map.unknownKeys(_priceRangeKeys).isEmpty,
      'PriceRange: unrecognised fields ${map.unknownKeys(_priceRangeKeys)}',
    );

    return PriceRange(min: map.decimalOr('min'), max: map.decimalOr('max'));
  }
}
