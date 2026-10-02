import '../../../core/cache/local_cache_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_payload_exception.dart';
import '../../../core/network/json_map.dart';
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
        cacheData.remove('shop_offers_v2');
        await _cache.put('$_cachePrefix$productId', cacheData);
        return details;
      }
      throw const ApiPayloadException(
        'product_details',
        'Response was not a JSON object',
      );
    } catch (e) {
      // On failure, try to serve cached product master info (without live
      // inventory). The cache is flagged so the UI can disclose the age —
      // serving it silently would present stale content as live, which is the
      // one thing the offline experience must never do.
      final cached = await _cache.get('$_cachePrefix$productId');
      if (cached != null && cached.data is Map<String, dynamic>) {
        final data = cached.data as Map<String, dynamic>;
        return _mapProductDetails(
          data,
          productId,
          fromCache: true,
          cachedAt: cached.cachedAt,
        );
      }
      rethrow;
    }
  }

  /// Maps the API response into a [ProductDetails] with clearly separated
  /// product master and shop inventory sections.
  ///
  /// [fromCache] and [cachedAt] carry provenance through to the model. They
  /// are not cosmetic: the model uses them to decide whether the screen must
  /// show "Last updated …" and to suppress availability claims entirely.
  ProductDetails _mapProductDetails(
    Map<String, dynamic> json,
    String productId, {
    bool fromCache = false,
    DateTime? cachedAt,
  }) {
    final root = JsonMap.tryParse(json);

    // ── PRODUCT MASTER (global static info) ─────────────────────────────
    // The master has lived at the top level, then under `product`, then under
    // `product_details` across API versions. `firstObjectOf` walks the aliases
    // newest-first, so a move costs an entry here rather than a crash.
    final productJson = root.firstObjectOf(['product', 'product_details']);
    // Falling back to the root means a flat response (the master fields sent
    // alongside everything else) still decodes.
    final master = productJson.isNotEmpty ? productJson : root;

    // Images: a single `image_url` plus a list, from either object.
    final images = <String>[
      if (master.string('image_url') != null) master.string('image_url')!,
      ...master.stringList('image_urls'),
      ...root.stringList('image_urls'),
    ];

    final variants = [
      for (final v in _variantList(master, root)) _mapVariant(v),
    ];
    final attributes = [
      for (final a in _attributeList(master, root)) _mapAttribute(a),
    ];
    final identifiers = [
      for (final i in _identifierList(master, root)) _mapIdentifier(i),
    ];

    final product = ProductMasterDetails(
      // The id falls back to the one the customer navigated to, so a response
      // that omits it still yields a usable model.
      id: master.string('id') ?? productId,
      name: master.stringOr('name'),
      brand: master.stringOr('brand'),
      category: master.stringOr('category'),
      subcategory: master.string('subcategory'),
      description: master.string('description'),
      shortDescription: master.string('short_description'),
      baseUnit: master.string('base_unit'),
      baseQuantity: master.decimal('base_quantity'),
      mrp: master.decimal('mrp'),
      priceRange: master.string('price_range'),
      imageUrls: images,
      variants: variants,
      attributes: attributes,
      identifiers: identifiers,
      // `is_saved` has been reported on the master and on the envelope.
      isSaved: master.booleanOr('is_saved') || root.booleanOr('is_saved'),
    );

    // ── SHOP INVENTORY (dynamic availability) ────────────────────────────
    // Never serve shop inventory from cache — it must always be live.
    final offers = fromCache
        ? <ShopInventoryOffer>[]
        : <ShopInventoryOffer>[
            for (final e in _offerList(root)) _mapShopOffer(e),
          ];

    return ProductDetails(
      product: product,
      shopOffers: offers,
      servedFromCache: fromCache,
      // Only meaningful alongside servedFromCache; a live fetch has no cache
      // timestamp and carrying a stale one would be actively misleading.
      cachedAt: fromCache ? cachedAt : null,
    );
  }

  /// Variants, from the master object or the envelope.
  ///
  /// A list helper rather than an inline `as List<dynamic>?` because that cast
  /// is the single most common crash in this file: the server sends an object
  /// instead of an array for a one-element collection, and the whole product
  /// page dies.
  static List<JsonMap> _variantList(JsonMap master, JsonMap root) {
    final list = master.list('variants').isNotEmpty
        ? master.list('variants')
        : root.list('variants');
    return list
        .whereType<Map<dynamic, dynamic>>()
        .map(JsonMap.tryParse)
        .toList();
  }

  static List<JsonMap> _attributeList(JsonMap master, JsonMap root) {
    final list = master.list('attributes').isNotEmpty
        ? master.list('attributes')
        : root.list('attributes');
    return list
        .whereType<Map<dynamic, dynamic>>()
        .map(JsonMap.tryParse)
        .toList();
  }

  static List<JsonMap> _identifierList(JsonMap master, JsonMap root) {
    final list = master.list('identifiers').isNotEmpty
        ? master.list('identifiers')
        : root.list('identifiers');
    return list
        .whereType<Map<dynamic, dynamic>>()
        .map(JsonMap.tryParse)
        .toList();
  }

  /// Shop offers, newest key first.
  static List<JsonMap> _offerList(JsonMap root) {
    const aliases = ['shop_offers', 'nearby_shops_offers', 'shop_inventories'];
    for (final key in aliases) {
      final list = root.list(key);
      if (list.isNotEmpty) {
        return list
            .whereType<Map<dynamic, dynamic>>()
            .map(JsonMap.tryParse)
            .toList();
      }
    }
    return const [];
  }

  ProductVariant _mapVariant(JsonMap json) {
    // `attributes_json` is a TEXT column holding JSON; malformed content yields
    // an empty map instead of breaking the variant. A newer API that sends the
    // attributes as a real object is picked up by the `attributes` alias.
    final nested = json.nestedJson('attributes_json');

    return ProductVariant(
      id: json.stringOr('id'),
      name: json.stringOr('name'),
      sku: json.string('sku'),
      description: json.string('description'),
      attributes: nested.isNotEmpty
          ? _stringifyMap(nested)
          : json.stringMap('attributes'),
    );
  }

  /// Flattens a decoded JSON object to `Map<String, String>`.
  static Map<String, String> _stringifyMap(JsonMap source) {
    final out = <String, String>{};
    source.raw.forEach((k, v) {
      if (v == null) return;
      if (v is Map || v is List) return;
      out[k] = v.toString();
    });
    return out;
  }

  ProductAttribute _mapAttribute(JsonMap json) {
    // `values` has been a list and has been a single scalar; both are accepted.
    final values = json.list('values').isNotEmpty
        ? json.list('values')
        : json.list('value');
    return ProductAttribute(
      name: json.stringOr('name'),
      values: values
          .map((e) {
            if (e is String) return e;
            if (e is Map) return (e['value'] ?? e['name'])?.toString() ?? '';
            return e.toString();
          })
          .where((s) => s.isNotEmpty)
          .toList(growable: false),
    );
  }

  ProductIdentifier _mapIdentifier(JsonMap json) {
    return ProductIdentifier(
      // `type`/`value` and `identifier_type`/`identifier_value` are both seen.
      type: json.firstOf(['identifier_type', 'type']) ?? '',
      value: json.firstOf(['identifier_value', 'value']) ?? '',
      isPrimary: json.booleanOr('is_primary'),
    );
  }

  ShopInventoryOffer _mapShopOffer(JsonMap json) {
    // A missing timestamp keeps the epoch sentinel so the shared freshness
    // formatter renders "Unknown". Stamping DateTime.now() here would make
    // inventory of unknown age look freshly verified.
    final lastUpdated =
        json.firstDateTimeOf(['last_updated', 'updated_at']) ??
        DateTime.fromMillisecondsSinceEpoch(0);

    return ShopInventoryOffer(
      shopId: json.stringOr('shop_id'),
      shopName: json.stringOr('shop_name'),
      shopImageUrl: json.stringOr('shop_image_url'),
      price: json.decimalOr('price'),
      mrp: json.decimal('mrp'),
      distanceInKm: json.decimalOr('distance_km'),
      rating: json.decimalOr('shop_rating'),
      // `is_available` is the primary signal; `stock_status` can stand in when
      // it is absent, but ONLY when it clearly says so (see isOutOfStock).
      isAvailable: json.firstBooleanOf(['is_available']) ?? false,
      lastUpdated: lastUpdated,
      stockStatus: json.firstOf(['stock_status', 'availability']),
      freshnessStatus: json.string('freshness_status'),
      offerText: json.string('offer_text'),
      // Null when the backend did not report it — the card then shows nothing
      // rather than guessing "Open".
      isOpenNow: json.firstBooleanOf(['is_open_now']),
      isAcceptingOrders: json.firstBooleanOf(['is_accepting_orders']),
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
