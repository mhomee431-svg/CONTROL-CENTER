import '../domain/search_repository.dart';
import '../domain/models/search_models.dart';

class MockSearchRepository implements SearchRepository {
  /// The single barcode this mock recognises.
  static const String _knownBarcode = '8901234567890';

  static const List<String> _recentSearches = [
    'Paracetamol 500mg',
    'Bosch Drill',
    'Ceiling Fan',
    'Dettol Handwash',
  ];

  static const List<String> _popularSearches = [
    'Bosch Drill',
    'Nivea',
    'Dettol',
    'Bajaj',
  ];

  @override
  Future<List<String>> getRecentSearches() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return _recentSearches;
  }

  @override
  Future<List<String>> getPopularSearches() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return _popularSearches;
  }

  @override
  Future<List<ShopProductResult>> lookupBarcode(
    String barcode, {
    double? latitude,
    double? longitude,
    int page = 1,
    int limit = 20,
  }) async {
    await Future.delayed(const Duration(milliseconds: 400));
    // Only the known demo barcode resolves; anything else is an honest miss so
    // the "not found" path can be exercised.
    if (barcode.trim() != _knownBarcode) return const [];
    // The demo payload is a single shop, so any page beyond the first is empty
    // by construction — same short-page contract as the real endpoint.
    if (page > 1) return const [];
    return [
      ShopProductResult(
        id: 'sp-barcode-1',
        productId: 'p1',
        productName: 'Bosch Impact Drill 13mm',
        productImageUrl: 'https://via.placeholder.com/300',
        shopId: 's1',
        shopName: 'Gupta Electronics',
        price: 2400,
        isAvailable: true,
        distanceInKm: 1.2,
        shopRating: 4.5,
        lastUpdated: DateTime(2026, 1, 1),
        availability: InventoryAvailability.inStock,
        freshness: FreshnessLevel.fresh,
      ),
    ];
  }

  @override
  Future<List<SearchSuggestion>> getSuggestions(String query) async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (query.isEmpty) return [];

    return [
      SearchSuggestion(text: '$query 500mg'),
      SearchSuggestion(text: '$query in Hardware', isCategory: true),
      SearchSuggestion(text: 'Samsung $query', isBrand: true),
      SearchSuggestion(text: '$query - Premium', isBrand: true),
    ];
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
    // Simulate network latency
    await Future.delayed(const Duration(milliseconds: 800));

    // Simulate server error for testing resilience
    if (query.toLowerCase() == 'error') {
      throw Exception('Simulated server error');
    }

    // Simulate no results for a specific query (empty state testing)
    if (query.toLowerCase() == 'no-results') {
      return [];
    }

    // Simulate end of pagination
    if (page > 3) return [];

    final now = DateTime.now();
    var results = List.generate(limit, (index) {
      final distance = 0.5 + (index * 0.2);
      final price = 150.0 + (index * 10);
      final mrp = price + 40.0 + (index % 3 == 0 ? 0 : 60.0);
      final rating = 4.5 - (index * 0.1);
      final lastUpdated = now.subtract(Duration(minutes: index * 15));
      // 1 in 4 out of stock, 1 in 5 low stock
      final availability = index % 4 == 0
          ? InventoryAvailability.outOfStock
          : (index % 5 == 0
                ? InventoryAvailability.lowStock
                : InventoryAvailability.inStock);

      return ShopProductResult(
        id: 'res_${page}_$index',
        productId: 'p_${page}_$index',
        productName: '$query - Model ${index + 1}',
        productImageUrl: 'https://via.placeholder.com/150',
        shopId: 's_${page}_$index',
        shopName: 'Local Shop ${index + 1}',
        price: price,
        isAvailable:
            availability == InventoryAvailability.inStock ||
            availability == InventoryAvailability.lowStock,
        distanceInKm: distance,
        shopRating: rating,
        lastUpdated: lastUpdated,
        variant: index % 2 == 0 ? '500g Pack' : '1L Pack',
        mrp: availability == InventoryAvailability.outOfStock ? null : mrp,
        shopImageUrl: 'https://via.placeholder.com/60',
        offerText: index == 0 ? '10% OFF' : null,
        shopAddress: 'Address ${index + 1}, Near Main Road',
        shopLatitude: 25.594 + (index * 0.001),
        shopLongitude: 85.137 - (index * 0.001),
        category: 'Household Goods',
        brand: index % 3 == 0 ? 'Dettol' : 'Local',
        reviewCount: 10 + index * 5,
        isOpenNow: index % 3 != 2,
        isAcceptingOrders: index % 3 != 2,
        availability: availability,
        freshness: _deriveFreshness(lastUpdated, now),
      );
    });

    // Apply local sorting to simulate backend sort behavior
    switch (sort) {
      case SortOption.nearest:
        results.sort((a, b) => a.distanceInKm.compareTo(b.distanceInKm));
        break;
      case SortOption.lowestPrice:
        results.sort((a, b) => a.price.compareTo(b.price));
        break;
      case SortOption.highestRated:
        results.sort((a, b) => b.shopRating.compareTo(a.shopRating));
        break;
      case SortOption.recentlyUpdated:
        results.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
        break;
      case SortOption.relevance:
        // Keep default backend ordering (no-op in mock).
        break;
      case SortOption.availability:
        // In-stock / purchasable first.
        results.sort((a, b) {
          final aPurchasable = a.isPurchasableNow ? 0 : 1;
          final bPurchasable = b.isPurchasableNow ? 0 : 1;
          return aPurchasable.compareTo(bPurchasable);
        });
        break;
      case SortOption.offers:
        results.sort((a, b) {
          final aHasOffer = (a.offerText != null || a.hasDiscount) ? 0 : 1;
          final bHasOffer = (b.offerText != null || b.hasDiscount) ? 0 : 1;
          return aHasOffer.compareTo(bHasOffer);
        });
        break;
    }

    // Apply filters locally to simulate backend filtering
    if (filters != null) {
      if (filters['max_distance'] is num) {
        final maxDistance = (filters['max_distance'] as num).toDouble();
        results = results.where((r) => r.distanceInKm <= maxDistance).toList();
      }
      if (filters['in_stock'] == true) {
        results = results.where((r) => r.isPurchasableNow).toList();
      }
      if (filters['min_price'] is num) {
        final minPrice = (filters['min_price'] as num).toDouble();
        results = results.where((r) => r.price >= minPrice).toList();
      }
      if (filters['max_price'] is num) {
        final maxPrice = (filters['max_price'] as num).toDouble();
        results = results.where((r) => r.price <= maxPrice).toList();
      }
      if (filters['min_rating'] is num) {
        final minRating = (filters['min_rating'] as num).toDouble();
        results = results.where((r) => r.shopRating >= minRating).toList();
      }
      if (filters['offers_only'] == true) {
        results = results
            .where((r) => r.offerText != null || r.hasDiscount)
            .toList();
      }
      if (filters['open_now'] == true) {
        results = results.where((r) => r.isOpenNow == true).toList();
      }
      if (filters['category'] is String) {
        final category = filters['category'] as String;
        results = results.where((r) => r.category == category).toList();
      }
      if (filters['brand'] is String) {
        final brand = filters['brand'] as String;
        results = results.where((r) => r.brand == brand).toList();
      }
    }

    return results;
  }

  FreshnessLevel _deriveFreshness(DateTime lastUpdated, DateTime now) {
    final age = now.difference(lastUpdated);
    if (age.inMinutes <= 30) return FreshnessLevel.fresh;
    if (age.inHours <= 6) return FreshnessLevel.recent;
    return FreshnessLevel.stale;
  }
}
