import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/product_models.dart';
import '../../domain/product_page.dart';
import '../../domain/product_query.dart';

/// The products list's VIEW state: the query the shopkeeper applied and how
/// far they have paged into its result.
///
/// This is deliberately separate from `ProductsState` (the catalog's DATA):
///   * The query belongs to ONE screen. The inventory scopes and the price list
///     read the same catalog rows through their OWN view state, so carrying the
///     products list's filter in the shared catalog state would let one
///     screen's filter leak into another's.
///   * It must OUTLIVE the screen. Leaving the tab, pulling to refresh or
///     opening Product Details can rebuild (or dispose) the list widget, and a
///     query kept in widget state is thrown away by every one of those trips —
///     which is exactly the "lost list state" this model exists to prevent.
///     Held by this provider, the search text, the filters, the sort and the
///     page all survive.
class ProductsListState {
  const ProductsListState({
    this.query = const ProductQuery(),
    this.visibleCount = productsPageSize,
  });

  /// Everything that narrows or orders the list.
  final ProductQuery query;

  /// How many matching rows the list currently reveals — grows by
  /// [productsPageSize] per [ProductsListController.showMore].
  final int visibleCount;
}

final productsListControllerProvider =
    NotifierProvider<ProductsListController, ProductsListState>(
      ProductsListController.new,
    );

/// The products list's ViewModel: it owns the query, the page window, and the
/// one derivation that turns catalog rows into the page on screen.
///
/// It performs NO I/O — the rows come from `ProductsController` — so every
/// method here is a synchronous, testable state transition.
class ProductsListController extends Notifier<ProductsListState> {
  /// The "apply the query to the catalog" derivation, kept cheap across
  /// keystrokes and rebuilds (see [ProductQueryCache]).
  final ProductQueryCache _rows = ProductQueryCache();

  @override
  ProductsListState build() => const ProductsListState();

  /// The page the list should render right now for [items]: [state.query]
  /// applied to the rows, cut at the current window.
  ProductPage pageFor(List<ShopProductItem> items) => ProductPage.of(
        matching(items),
        total: items.length,
        visibleCount: state.visibleCount,
      );

  /// Every row of [items] the query keeps, in the query's order.
  ///
  /// Memoized against the (catalog, query) pair, so a keystroke re-runs the
  /// predicate but never re-indexes the catalog, and an unrelated rebuild runs
  /// neither.
  List<ShopProductItem> matching(List<ShopProductItem> items) =>
      _rows.rows(items, state.query);

  /// Narrows by typed text.
  void setSearch(String value) => _setQuery(state.query.withSearch(value));

  /// Narrows to one stock scope ([ProductQuery.stockAll] shows everything).
  void setStock(String scope) => _setQuery(state.query.withStock(scope));

  /// Reorders the list.
  void setSort(ProductSort sort) => _setQuery(state.query.withSort(sort));

  /// Applies the filter sheet's result. The sheet is handed the live query and
  /// returns it with only the filter facets replaced, so the search text and
  /// the stock scope the shopkeeper set outside the sheet are never lost.
  void setFilters(ProductQuery query) => _setQuery(query);

  /// Drops the search text AND every filter.
  ///
  /// The SORT is kept: "Clear" answers "show me the whole shop again", not
  /// "forget how I like the list ordered".
  void clear() => _setQuery(ProductQuery(sort: state.query.sort));

  /// Reveals the next page of the current result.
  ///
  /// Safe to call at the end of the list: the window is clamped by the number
  /// of matching rows, so an over-wide window renders exactly the same page.
  void showMore() => state = ProductsListState(
    query: state.query,
    visibleCount: state.visibleCount + productsPageSize,
  );

  void _setQuery(ProductQuery query) {
    if (query == state.query) return;
    // A new question means a new result set: page from the top again, so the
    // shopkeeper never lands in the middle of a list they have not seen.
    state = ProductsListState(query: query);
  }
}
