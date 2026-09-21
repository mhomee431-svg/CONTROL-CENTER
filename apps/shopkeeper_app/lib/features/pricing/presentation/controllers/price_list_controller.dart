import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../products/domain/product_models.dart';
import '../../../products/domain/product_page.dart';
import '../../../products/domain/product_query.dart';

/// The price list's VIEW state: the search text the shopkeeper typed and how
/// far they have paged through the price book.
class PriceListState {
  const PriceListState({
    this.query = const ProductQuery(sort: ProductSort.asListed),
    this.visibleCount = productsPageSize,
  });

  /// Only the search facet is user-editable — the price list reads the catalog
  /// in the server's own order, with no filters of its own.
  final ProductQuery query;

  /// How many matching rows the list currently reveals — grows by
  /// [productsPageSize] per [PriceListController.showMore].
  final int visibleCount;
}

final priceListControllerProvider =
    NotifierProvider<PriceListController, PriceListState>(
  PriceListController.new,
);

/// The price list's ViewModel: it owns the search text, the page window and
/// the one derivation that turns catalog rows into the page on screen.
///
/// Like every list ViewModel it performs NO I/O — the rows come from
/// `ProductsController` — so each method is a synchronous, testable state
/// transition.
class PriceListController extends Notifier<PriceListState> {
  /// The "apply the query to the catalog" derivation, kept cheap across
  /// keystrokes and rebuilds (see [ProductQueryCache]).
  final ProductQueryCache _rows = ProductQueryCache();

  @override
  PriceListState build() =>
      const PriceListState(query: ProductQuery(sort: ProductSort.asListed));

  /// The page the price list should render right now for [items].
  ProductPage pageFor(List<ShopProductItem> items) => ProductPage.of(
        matching(items),
        total: items.length,
        visibleCount: state.visibleCount,
      );

  /// Every row of [items] the search text keeps, in the server's order.
  /// Memoized against the (catalog, query) pair.
  List<ShopProductItem> matching(List<ShopProductItem> items) =>
      _rows.rows(items, state.query);

  /// Narrows by typed text.
  void setSearch(String value) => _setQuery(state.query.withSearch(value));

  /// Clears the search text (the price list has no other filter to clear).
  void clear() => _setQuery(state.query.withSearch(''));

  /// Reveals the next page of the current result.
  ///
  /// Safe to call at the end of the list: the window is clamped by the number
  /// of matching rows, so an over-wide window renders exactly the same page.
  void showMore() => state = PriceListState(
        query: state.query,
        visibleCount: state.visibleCount + productsPageSize,
      );

  void _setQuery(ProductQuery query) {
    if (query == state.query) return;
    // A new question means a new result set: page from the top again.
    state = PriceListState(query: query);
  }
}
