import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/product_models.dart';
import '../../domain/product_query.dart';
import '../../domain/product_search.dart';

/// How many matching rows one page of the products list reveals.
///
/// A shop is paged in memory (the whole catalog arrives in ONE `view=list`
/// response), so this is a RENDER window, not a second request: it keeps the
/// list's work proportional to what the shopkeeper is looking at instead of to
/// the size of their catalog, and it gives the state a page to advance.
const int productsPageSize = 50;

/// The products list's VIEW state: the query the shopkeeper applied and how
/// far they have paged into its result.
///
/// This is deliberately separate from `ProductsState` (the catalog's DATA):
///   * The query belongs to ONE screen. The inventory scopes and the price list
///     read the same catalog rows through their OWN query, so carrying the
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

/// One page of the products list, with the counters the screen renders.
class ProductPage {
  const ProductPage({
    required this.rows,
    required this.matched,
    required this.total,
    required this.hasMore,
  });

  /// The rows to render now: the query's result, cut at the current page.
  final List<ShopProductItem> rows;

  /// Rows the query matched across the whole catalog.
  final int matched;

  /// Rows in the catalog, ignoring the query.
  final int total;

  /// True when the query matched rows the current page does not show yet.
  final bool hasMore;

  /// Matched rows still waiting behind the page break.
  int get hidden => matched - rows.length;

  /// The catalog itself is empty — the feature's own empty state, not "no
  /// results".
  bool get isEmptyCatalog => total == 0;

  /// The catalog has rows, but the query matched none of them.
  bool get isNoMatch => total > 0 && matched == 0;
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
  /// The catalog's searchable text, indexed once per catalog instance.
  ///
  /// It lives on the controller rather than in the state on purpose: every
  /// keystroke REPLACES the state, and an index held there would be rebuilt
  /// (four `toLowerCase` allocations per row) on each character typed.
  final ProductSearchCache _searchIndex = ProductSearchCache();

  /// Last derivation, with the inputs it was built from: the catalog instance
  /// and the query. A rebuild that changed neither (a snackbar, an
  /// availability flip, a page turn) reuses it instead of re-running the
  /// predicate over every product.
  List<ShopProductItem>? _memoRows;
  List<ShopProductItem>? _memoSource;
  ProductQuery? _memoQuery;

  @override
  ProductsListState build() => const ProductsListState();

  /// The page the list should render right now for [items]: [state.query]
  /// applied to the rows, cut at the current window.
  ProductPage pageFor(List<ShopProductItem> items) {
    final matched = matching(items);
    final rows = matched.length <= state.visibleCount
        ? matched
        : matched.sublist(0, state.visibleCount);
    return ProductPage(
      rows: rows,
      matched: matched.length,
      total: items.length,
      hasMore: rows.length < matched.length,
    );
  }

  /// Every row of [items] the query keeps, in the query's order.
  ///
  /// Memoized against the (catalog, query) pair, so a keystroke re-runs the
  /// predicate but never re-indexes the catalog, and an unrelated rebuild runs
  /// neither.
  List<ShopProductItem> matching(List<ShopProductItem> items) {
    if (identical(_memoSource, items) && _memoQuery == state.query) {
      return _memoRows!;
    }
    final rows = state.query.apply(items, _searchIndex.of(items));
    _memoSource = items;
    _memoQuery = state.query;
    _memoRows = rows;
    return rows;
  }

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
