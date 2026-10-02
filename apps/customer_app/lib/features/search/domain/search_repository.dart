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
    Map<String, dynamic>?
    filters, // e.g., {'max_distance': 5.0, 'in_stock': true}
    double? latitude,
    double? longitude,
  });

  /// Looks up the shops selling the product identified by [barcode].
  ///
  /// Returns an empty list when the barcode is unknown to the platform — never
  /// a placeholder product.
  ///
  /// Bounded by the same backend pagination contract as every other search
  /// list: `page` is 1-based and `limit` is required, so a product stocked by
  /// many shops cannot materialise an unbounded catalogue into one response.
  /// Defaults (`page: 1`, `limit: 20`) preserve the old one-shot shape for the
  /// common single-page barcode flow.
  Future<List<ShopProductResult>> lookupBarcode(
    String barcode, {
    double? latitude,
    double? longitude,
    int page = 1,
    int limit = 20,
  });
}
