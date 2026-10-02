import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/enum_codec.dart';
import '../../../core/network/json_map.dart';
import '../domain/search_repository.dart';
import '../domain/models/search_models.dart';

/// Real backend implementation of [SearchRepository].
class ApiSearchRepository implements SearchRepository {
  final ApiClient _apiClient;

  ApiSearchRepository(this._apiClient);

  @override
  Future<List<String>> getRecentSearches() async {
    // Recent searches are stored locally; the backend does not persist them in Phase 13.
    return [];
  }

  @override
  Future<List<String>> getPopularSearches() async {
    // Real popularity comes from aggregated platform searches
    // (GET /search/v2/popular). When the platform has no search history yet
    // (fresh database / new deployment) or the call fails, this returns an
    // empty list so the UI hides the section — never a hardcoded starter list,
    // which would be indistinguishable from genuine popularity data.
    try {
      final data = await _apiClient.get(
        ApiEndpoints.searchPopular,
        requiresAuth: false,
      );
      if (data is List) {
        return data
            .whereType<Map<String, dynamic>>()
            .map((e) => e['query']?.toString() ?? '')
            .where((q) => q.isNotEmpty)
            .toList();
      }
    } catch (_) {
      // Fall through to an empty list below.
    }
    return [];
  }

  @override
  Future<List<ShopProductResult>> lookupBarcode(
    String barcode, {
    double? latitude,
    double? longitude,
    int page = 1,
    int limit = 20,
  }) async {
    final data = await _apiClient.get(
      ApiEndpoints.searchBarcode(Uri.encodeComponent(barcode.trim())),
      queryParameters: {
        'latitude': ?latitude,
        'longitude': ?longitude,
        'page': page,
        'limit': limit,
      },
      requiresAuth: false,
    );

    if (data is List) {
      // A row that is not an object is dropped rather than crashing the scan.
      return data
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => _mapBarcodeHit(JsonMap.tryParse(e)))
          .toList(growable: false);
    }
    return const [];
  }

  /// Maps one `GET /search/v2/barcodes/{barcode}` hit onto [ShopProductResult].
  ///
  /// The barcode payload omits the product image and reports nullable price /
  /// distance, so those stay empty rather than being invented.
  static ShopProductResult _mapBarcodeHit(JsonMap json) {
    // A scanned product carries the same freshness evidence as a typed one.
    // A missing timestamp keeps the epoch sentinel, which the shared freshness
    // formatter renders as "Unknown" instead of a fabricated "just now".
    final lastUpdated = json.firstDateTimeOf([
      'last_inventory_update',
      'last_updated',
    ]);
    return ShopProductResult(
      id: json.stringOr('shop_product_id'),
      productId: json.stringOr('product_id'),
      productName: json.stringOr('product_name'),
      productImageUrl: '',
      shopId: json.stringOr('shop_id'),
      shopName: json.stringOr('shop_name'),
      price: json.decimalOr('price'),
      isAvailable: json.booleanOr('is_available'),
      distanceInKm: json.decimalOr('distance_km'),
      shopRating: json.decimalOr('shop_rating'),
      lastUpdated: lastUpdated ?? DateTime.fromMillisecondsSinceEpoch(0),
      brand: json.string('brand_name'),
      category: json.string('category_name'),
      mrp: json.decimal('mrp'),
      // Barcode hits carry the same open/order-acceptance enrichment as text
      // search (engine attaches it), so a scanned and a typed product agree.
      isOpenNow: json.firstBooleanOf(['is_open_now']),
      isAcceptingOrders: json.firstBooleanOf(['is_accepting_orders']),
      availability: _availabilityFrom(json),
      freshness: _parseFreshnessStatus(json),
      freshnessStatusRaw: json.string('freshness_status'),
    );
  }

  /// Availability for the barcode hit, which reports `stock_status` directly.
  static InventoryAvailability _availabilityFrom(JsonMap json) =>
      enumCodec<InventoryAvailability>(
        json.firstOf(['stock_status', 'availability']),
        InventoryAvailability.values,
        InventoryAvailability.unknown,
      );

  @override
  Future<List<SearchSuggestion>> getSuggestions(String query) async {
    final data = await _apiClient.get(
      ApiEndpoints.searchSuggestions,
      queryParameters: {'q': query},
      requiresAuth: false,
    );

    if (data is List) {
      // Suggestions are a small freezed model; a row that cannot be decoded is
      // skipped so one odd entry cannot empty the whole suggestion list.
      final out = <SearchSuggestion>[];
      for (final entry in data) {
        if (entry is! Map) continue;
        try {
          out.add(SearchSuggestion.fromJson(entry.cast<String, dynamic>()));
        } catch (_) {
          // A malformed suggestion is not worth failing the whole list over.
        }
      }
      return out;
    }
    return const [];
  }

  @override
  Future<List<ShopProductResult>> searchProducts({
    required String query,
    required int page,
    required int limit,
    SortOption sort = kDefaultSortOption,
    Map<String, dynamic>? filters,
    double? latitude,
    double? longitude,
  }) async {
    final sortValue = switch (sort) {
      SortOption.nearest => 'nearest',
      SortOption.lowestPrice => 'lowest_price',
      SortOption.highestRated => 'highest_rated',
      SortOption.recentlyUpdated => 'recently_updated',
      SortOption.relevance => 'relevance',
      SortOption.availability => 'availability',
      SortOption.offers => 'offers',
    };

    final queryParameters = <String, dynamic>{
      'q': query,
      'page': page,
      'limit': limit,
      'sort': sortValue,
      'latitude': ?latitude,
      'longitude': ?longitude,
      if (filters?['in_stock'] == true) 'in_stock': true,
      if (filters?['offers_only'] == true) 'offers_only': true,
      if (filters?['open_now'] == true) 'open_now': true,
      if (filters?['max_distance'] is num)
        'radius_km': (filters!['max_distance'] as num).toDouble(),
      if (filters?['min_rating'] is num)
        'min_rating': (filters!['min_rating'] as num).toDouble(),
      if (filters?['min_price'] is num)
        'min_price': (filters!['min_price'] as num).toDouble(),
      if (filters?['max_price'] is num)
        'max_price': (filters!['max_price'] as num).toDouble(),
      if (filters?['category'] != null) 'category': filters!['category'],
      if (filters?['brand'] != null) 'brand': filters!['brand'],
    };

    final data = await _apiClient.get(
      ApiEndpoints.searchProducts,
      queryParameters: queryParameters,
      requiresAuth: false,
    );

    final root = JsonMap.tryParse(data);
    if (root.has('results')) {
      // A malformed row costs that row, not the whole results page.
      return root.objectList('results').map(_mapResult).toList(growable: false);
    }
    return const [];
  }

  ShopProductResult _mapResult(JsonMap json) {
    // The search index publishes `last_inventory_update`; `last_updated` is
    // accepted as a tolerated alias. When neither is present we keep null so
    // freshness falls back to the explicit `freshness_status` instead of being
    // derived from a fabricated "now".
    final lastUpdated = json.firstDateTimeOf([
      'last_inventory_update',
      'last_updated',
    ]);
    final availability = _parseAvailability(json);
    final freshness = lastUpdated != null
        ? _deriveFreshness(lastUpdated)
        : _parseFreshnessStatus(json);

    return ShopProductResult(
      // The search index exposes the offer-level id as `id`, with
      // `shop_product_id` accepted as an alias.
      id: json.firstOf(['id', 'shop_product_id']) ?? '',
      productId: json.stringOr('product_id'),
      productName: json.stringOr('product_name'),
      productImageUrl: json.stringOr('product_image_url'),
      shopId: json.stringOr('shop_id'),
      shopName: json.stringOr('shop_name'),
      price: json.decimalOr('price'),
      isAvailable: json.booleanOr('is_available'),
      distanceInKm: json.decimalOr('distance_km'),
      shopRating: json.decimalOr('shop_rating'),
      // Unknown timestamp stays an explicit sentinel. Stamping DateTime.now()
      // here would make stale inventory look freshly verified.
      lastUpdated: lastUpdated ?? DateTime.fromMillisecondsSinceEpoch(0),
      variant: json.string('variant'),
      mrp: json.decimal('mrp'),
      shopImageUrl: json.string('shop_image_url'),
      offerText: json.string('offer_text'),
      shopAddress: json.string('shop_address'),
      shopLatitude: json.decimal('shop_latitude'),
      shopLongitude: json.decimal('shop_longitude'),
      category: json.firstOf(['category', 'category_name']),
      brand: json.firstOf(['brand', 'brand_name']),
      reviewCount: json.integer('review_count'),
      // Backend's open/order-acceptance evaluation. Null means "not reported",
      // which the card renders as nothing rather than guessing.
      isOpenNow: json.firstBooleanOf(['is_open_now']),
      isAcceptingOrders: json.firstBooleanOf(['is_accepting_orders']),
      availability: availability,
      freshness: freshness,
      freshnessStatusRaw: json.string('freshness_status'),
    );
  }

  InventoryAvailability _parseAvailability(JsonMap json) {
    // `stock_status` and `availability` are two names for one idea, newest first.
    final raw = json.firstOf([
      'availability',
      'stock_status',
      'availability_status',
    ]);
    final parsed = enumCodec<InventoryAvailability>(
      raw,
      InventoryAvailability.values,
      InventoryAvailability.unknown,
    );
    if (parsed != InventoryAvailability.unknown) return parsed;

    // A status this build has never heard of still tells us something: the
    // server had an opinion. Fall back to the boolean, then to unknown.
    if (json.has('is_available')) {
      return json.booleanOr('is_available')
          ? InventoryAvailability.inStock
          : InventoryAvailability.outOfStock;
    }
    return InventoryAvailability.unknown;
  }

  FreshnessLevel _deriveFreshness(DateTime lastUpdated) {
    final age = DateTime.now().difference(lastUpdated);
    if (age.inMinutes <= 30) return FreshnessLevel.fresh;
    if (age.inHours <= 6) return FreshnessLevel.recent;
    return FreshnessLevel.stale;
  }

  /// Maps the backend's inventory freshness classification
  /// (RECENTLY_UPDATED / STALE / None) onto the UI freshness levels.
  ///
  /// Static so the barcode hit mapper and the result mapper share one
  /// implementation — a scanned and a typed product must never classify
  /// freshness differently.
  ///
  /// An unrecognised status (a backend adding `VERY_STALE`) becomes
  /// [FreshnessLevel.unknown] rather than throwing, so one new value cannot
  /// take down the results list.
  static FreshnessLevel _parseFreshnessStatus(JsonMap json) =>
      enumCodec<FreshnessLevel>(
        json.string('freshness_status'),
        FreshnessLevel.values,
        FreshnessLevel.unknown,
      );
}
