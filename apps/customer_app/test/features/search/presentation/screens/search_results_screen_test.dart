import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_app/features/search/domain/models/search_models.dart';
import 'package:hyperlocal_app/features/search/domain/search_repository.dart';
import 'package:hyperlocal_app/features/search/presentation/screens/search_results_screen.dart';

/// Serves one fixed result so the screen reaches the results stage.
class _StubSearchRepository implements SearchRepository {
  @override
  Future<List<ShopProductResult>> searchProducts({
    required String query,
    required int page,
    required int limit,
    SortOption sort = SortOption.nearest,
    Map<String, dynamic>? filters,
    double? latitude,
    double? longitude,
  }) async {
    return [
      ShopProductResult(
        id: 'r1',
        productId: 'p1',
        productName: 'Dove Shampoo 650ml',
        productImageUrl: '',
        shopId: 's1',
        shopName: 'Gupta Electronics',
        price: 240,
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
  Future<List<String>> getPopularSearches() async => const [];

  @override
  Future<List<String>> getRecentSearches() async => const [];

  @override
  Future<List<SearchSuggestion>> getSuggestions(String query) async => const [];

  @override
  Future<List<ShopProductResult>> lookupBarcode(
    String barcode, {
    double? latitude,
    double? longitude,
  }) async => const [];
}

void main() {
  testWidgets('shows the spec header Search Results for "<query>"', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [searchRepositoryProvider.overrideWithValue(_StubSearchRepository())],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: SearchResultsScreen(query: 'Dove Shampoo'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('Search Results for "Dove Shampoo"'),
      findsOneWidget,
    );
    // The count line below is complementary, not a replacement.
    expect(find.text('1 results for "Dove Shampoo"'), findsOneWidget);
  });
}