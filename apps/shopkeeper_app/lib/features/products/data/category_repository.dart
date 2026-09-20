import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_providers.dart';
import '../domain/category_taxonomy.dart';

/// Product taxonomy contract.
abstract class CategoryRepository {
  Future<CategoryTaxonomy> fetchTaxonomy(String token);
}

class ApiCategoryRepository implements CategoryRepository {
  ApiCategoryRepository(this._api);

  final ApiClient _api;

  @override
  Future<CategoryTaxonomy> fetchTaxonomy(String token) async {
    final data = await _api.get(
      ApiEndpoints.productCategories,
      token: token,
    );
    return CategoryTaxonomy(CategoryOption.listFrom(data));
  }
}

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return ApiCategoryRepository(ref.watch(apiClientProvider));
});