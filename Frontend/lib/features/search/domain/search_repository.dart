import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../data/api_search_repository.dart';
import 'models/search_models.dart';

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return ApiSearchRepository(ref.watch(apiClientProvider));
});

abstract class SearchRepository {
  Future<List<String>> getRecentSearches();
  Future<List<String>> getPopularSearches();
  Future<List<SearchSuggestion>> getSuggestions(String query);

  /// Prepares the frontend for Elasticsearch pagination, filtering, and sorting
  Future<List<ShopProductResult>> searchProducts({
    required String query,
    required int page,
    required int limit,
    SortOption sort = SortOption.nearest,
    Map<String, dynamic>? filters, // e.g., {'max_distance': 5.0, 'in_stock': true}
    double? latitude,
    double? longitude,
  });
}