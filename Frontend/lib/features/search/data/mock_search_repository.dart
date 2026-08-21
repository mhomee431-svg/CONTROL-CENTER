import '../domain/search_repository.dart';
import '../domain/models/search_models.dart';

class MockSearchRepository implements SearchRepository {
  static const List<String> _recentSearches = [
    'Paracetamol 500mg',
    'Amul Butter',
    'Ceiling Fan',
    'Dettol Handwash',
  ];

  static const List<String> _popularSearches = [
    'Samsung Galaxy',
    'Aashirvaad Atta',
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
  Future<List<SearchSuggestion>> getSuggestions(String query) async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (query.isEmpty) return [];

    return [
      SearchSuggestion(text: '$query 500mg'),
      SearchSuggestion(text: '$query in Electronics', isCategory: true),
      SearchSuggestion(text: 'Samsung $query', isBrand: true),
      SearchSuggestion(text: '$query - Premium', isBrand: true),
    ];
  }

  @override
  Future<List<ShopProductResult>> searchProducts({
    required String query,
    required int page,
    required int limit,
    SortOption sort = SortOption.nearest,
    Map<String, dynamic>? filters,
  }) async {
    // Simulate network latency
    await Future.delayed(const Duration(milliseconds: 800));

    // Simulate server error for testing resilience
    if (query.toLowerCase() == 'error') {
      throw Exception('Simulated server error');
    }

    // Simulate end of pagination
    if (page > 3) return [];

    var results = List.generate(limit, (index) {
      final distance = 0.5 + (index * 0.2);
      final price = 150.0 + (index * 10);
      final rating = 4.5 - (index * 0.1);
      final lastUpdated = DateTime.now().subtract(Duration(minutes: index * 15));

      return ShopProductResult(
        id: 'res_${page}_$index',
        productId: 'p_${page}_$index',
        productName: '$query - Model ${index + 1}',
        productImageUrl: 'https://via.placeholder.com/150',
        shopId: 's_${page}_$index',
        shopName: 'Local Shop ${index + 1}',
        price: price,
        isAvailable: index % 4 != 0, // 1 in 4 out of stock
        distanceInKm: distance,
        shopRating: rating,
        lastUpdated: lastUpdated,
        offerText: index == 0 ? '10% OFF' : null,
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
    }

    // Apply filters locally to simulate backend filtering
    if (filters != null) {
      if (filters['max_distance'] is double) {
        final maxDistance = filters['max_distance'] as double;
        results = results.where((r) => r.distanceInKm <= maxDistance).toList();
      }
      if (filters['in_stock'] == true) {
        results = results.where((r) => r.isAvailable).toList();
      }
    }

    return results;
  }
}