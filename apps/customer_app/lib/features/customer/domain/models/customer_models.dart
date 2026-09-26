/// Domain models for customer features (favourites, recently viewed, share).
library;

/// Plain Dart classes — no code generation required so they work standalone.

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

  factory CustomerFavorite.fromJson(Map<String, dynamic> json) =>
      CustomerFavorite(
        id: json['id'] as int,
        itemType: json['item_type'] as String? ?? '',
        itemId: json['item_id'] as int? ?? 0,
        metadataJson: json['metadata_json'] as Map<String, dynamic>?,
        createdAt: json['created_at'] as String?,
        item: json['item'] != null
            ? FavouriteItem.fromJson(json['item'] as Map<String, dynamic>)
            : null,
      );
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

  factory FavouriteItem.fromJson(Map<String, dynamic> json) => FavouriteItem(
    id: json['id'] as int? ?? 0,
    name: json['name'] as String? ?? '',
    slug: json['slug'] as String?,
    imageUrl: json['image_url'] as String?,
  );
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

  factory RecentProduct.fromJson(Map<String, dynamic> json) => RecentProduct(
    productMasterId: json['product_master_id'] as int? ?? 0,
    name: json['name'] as String? ?? '',
    slug: json['slug'] as String?,
    imageUrl: json['image_url'] as String?,
    variantId: json['variant_id'] as int?,
    shopProductId: json['shop_product_id'] as int?,
    viewCount: json['view_count'] as int?,
    lastViewedAt: json['last_viewed_at'] as String?,
  );
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

  factory ProductSharePayload.fromJson(Map<String, dynamic> json) =>
      ProductSharePayload(
        productMasterId: json['product_master_id'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        slug: json['slug'] as String?,
        description: json['description'] as String?,
        imageUrl: json['image_url'] as String?,
        shopCount: json['shop_count'] as int?,
        priceRange: json['price_range'] != null
            ? PriceRange.fromJson(json['price_range'] as Map<String, dynamic>)
            : null,
        currency: json['currency'] as String?,
      );
}

class PriceRange {
  final double min;
  final double max;

  const PriceRange({required this.min, required this.max});

  factory PriceRange.fromJson(Map<String, dynamic> json) => PriceRange(
    min: (json['min'] as num?)?.toDouble() ?? 0,
    max: (json['max'] as num?)?.toDouble() ?? 0,
  );
}
