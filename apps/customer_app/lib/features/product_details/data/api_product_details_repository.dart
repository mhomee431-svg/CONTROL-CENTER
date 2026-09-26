import 'dart:convert';

import '../../../core/cache/local_cache_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../domain/product_details_repository.dart';
import '../domain/models/product_details_models.dart';

/// Real backend implementation of [ProductDetailsRepository] with local caching
/// for offline resilience. Inventory/availability data is never cached to avoid
/// presenting stale stock as confirmed live stock.
///
/// The API contract separates:
///   - **Product Master** (global static info) — cached for offline use
///   - **Shop Inventory** (dynamic availability) — always fetched live
class ApiProductDetailsRepository implements ProductDetailsRepository {
  final ApiClient _apiClient;
  final LocalCacheService _cache;
  final double? latitude;
  final double? longitude;

  static const String _cachePrefix = 'product_details_';

  ApiProductDetailsRepository(
    this._apiClient,
    this._cache, {
    this.latitude,
    this.longitude,
  });

  @override
  Future<ProductDetails> getProductDetails(String productId) async {
    try {
      // Fetch product master + shop inventory in one call.
      final data = await _apiClient.get(
        ApiEndpoints.product(productId),
        queryParameters: {
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
          // Keep the radius explicit so the product page and search page use
          // the same local-discovery boundary.
          'radius_km': 25.0,
        },
        requiresAuth: false,
      );

      if (data is Map<String, dynamic>) {
        final details = _mapProductDetails(data, productId);

        // Cache ONLY the product master (non-inventory) data for offline use.
        // Strip inventory/availability data before caching.
        final cacheData = Map<String, dynamic>.from(data);
        cacheData.remove('shop_inventories');
        cacheData.remove('nearby_shops_offers');
        cacheData.remove('shop_offers');
        await _cache.put('$_cachePrefix$productId', cacheData);
        return details;
      }
      throw Exception('Invalid product details response');
    } catch (e) {
      // On failure, try to serve cached product master info (without live inventory).
      final cached = await _cache.get('$_cachePrefix$productId');
      if (cached != null && cached.data is Map<String, dynamic>) {
        final data = cached.data as Map<String, dynamic>;
        return _mapProductDetails(data, productId, fromCache: true);
      }
      rethrow;
    }
  }

  /// Maps the API response into a [ProductDetails] with clearly separated
  /// product master and shop inventory sections.
  ProductDetails _mapProductDetails(
    Map<String, dynamic> json,
    String productId, {
    bool fromCache = false,
  }) {
    // ── PRODUCT MASTER (global static info) ─────────────────────────────
    final productJson =
        (json['product'] ?? json['product_details'] ?? json)
            as Map<String, dynamic>;

    final images = <String>[
      if (productJson['image_url'] != null) productJson['image_url'].toString(),
      ...?((productJson['image_urls'] ?? json['image_urls']) as List<dynamic>?)
          ?.map((e) => e.toString()),
    ];

    final variants = <ProductVariant>[
      ...?((productJson['variants'] ?? json['variants']) as List<dynamic>?)
          ?.map((e) => _mapVariant(e as Map<String, dynamic>)),
    ];

    final attributes = <ProductAttribute>[
      ...?((productJson['attributes'] ?? json['attributes']) as List<dynamic>?)
          ?.map((e) => _mapAttribute(e as Map<String, dynamic>)),
    ];

    final identifiers = <ProductIdentifier>[
      ...?((productJson['identifiers'] ?? json['identifiers'])
              as List<dynamic>?)
          ?.map((e) => _mapIdentifier(e as Map<String, dynamic>)),
    ];

    final product = ProductMasterDetails(
      id: productJson['id']?.toString() ?? productId,
      name: productJson['name']?.toString() ?? '',
      brand: productJson['brand']?.toString() ?? '',
      category: productJson['category']?.toString() ?? '',
      subcategory: productJson['subcategory']?.toString(),
      description: productJson['description']?.toString(),
      shortDescription: productJson['short_description']?.toString(),
      baseUnit: productJson['base_unit']?.toString(),
      baseQuantity: (productJson['base_quantity'] as num?)?.toDouble(),
      mrp: (productJson['mrp'] as num?)?.toDouble(),
      priceRange: productJson['price_range']?.toString(),
      imageUrls: images,
      variants: variants,
      attributes: attributes,
      identifiers: identifiers,
      isSaved: productJson['is_saved'] == true || json['is_saved'] == true,
    );

    // ── SHOP INVENTORY (dynamic availability) ────────────────────────────
    // Never serve shop inventory from cache — it must always be live.
    final offers = fromCache
        ? <ShopInventoryOffer>[]
        : <ShopInventoryOffer>[
            ...?((json['shop_inventories'] ??
                        json['nearby_shops_offers'] ??
                        json['shop_offers'])
                    as List<dynamic>?)
                ?.map((e) => _mapShopOffer(e as Map<String, dynamic>)),
          ];

    return ProductDetails(product: product, shopOffers: offers);
  }

  ProductVariant _mapVariant(Map<String, dynamic> json) {
    Map<String, String> attrs = {};
    final attrsJson = json['attributes_json']?.toString();
    if (attrsJson != null) {
      try {
        final decoded = jsonDecode(attrsJson);
        if (decoded is Map<String, dynamic>) {
          attrs = decoded.map((k, v) => MapEntry(k, v.toString()));
        }
      } catch (_) {
        // Ignore malformed attributes_json
      }
    }
    return ProductVariant(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      sku: json['sku']?.toString(),
      description: json['description']?.toString(),
      attributes: attrs,
    );
  }

  ProductAttribute _mapAttribute(Map<String, dynamic> json) {
    return ProductAttribute(
      name: json['name']?.toString() ?? '',
      values: [
        ...?((json['values'] ?? json['value']) as List<dynamic>?)?.map(
          (e) => e is Map<String, dynamic>
              ? e['value']?.toString() ?? ''
              : e.toString(),
        ),
      ],
    );
  }

  ProductIdentifier _mapIdentifier(Map<String, dynamic> json) {
    return ProductIdentifier(
      type:
          json['identifier_type']?.toString() ?? json['type']?.toString() ?? '',
      value:
          json['identifier_value']?.toString() ??
          json['value']?.toString() ??
          '',
      isPrimary: json['is_primary'] == true,
    );
  }

  ShopInventoryOffer _mapShopOffer(Map<String, dynamic> json) {
    return ShopInventoryOffer(
      shopId: json['shop_id']?.toString() ?? '',
      shopName: json['shop_name']?.toString() ?? '',
      shopImageUrl: json['shop_image_url']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      mrp: (json['mrp'] as num?)?.toDouble(),
      distanceInKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
      rating: (json['shop_rating'] as num?)?.toDouble() ?? 0,
      isAvailable: json['is_available'] == true,
      lastUpdated:
          DateTime.tryParse(json['last_updated']?.toString() ?? '') ??
          DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
      stockStatus: json['stock_status']?.toString(),
      freshnessStatus: json['freshness_status']?.toString(),
      offerText: json['offer_text']?.toString(),
    );
  }

  @override
  Future<void> toggleSaveProduct(String productId, bool save) async {
    if (save) {
      await _apiClient.post(ApiEndpoints.savedProduct(productId));
    } else {
      await _apiClient.delete(ApiEndpoints.savedProduct(productId));
    }
  }
}
