import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../products/domain/product_models.dart';
import '../../../products/domain/product_page.dart';
import '../../../products/domain/product_query.dart';
import '../../domain/inventory_scope.dart';

/// One inventory scope list's VIEW state: the search text the shopkeeper typed
/// and how far they have paged into the slice.
///
/// The slice itself is NOT part of this state — it is the [arg] the provider
/// family is keyed by. Four scope routes are alive side by side in the shell's
/// indexed stack, so a single shared state would have one route's search
/// overwrite another's; one provider per scope keeps every route's list state
/// its own.
class InventoryScopeState {
  const InventoryScopeState({
    this.query = const ProductQuery(),
    this.visibleCount = productsPageSize,
  });

  /// The shopkeeper's OWN question: the search text plus every filter facet
  /// they applied (category, freshness, and — when the scope does not pin a
  /// stock slice — the stock chips). The scope's own slice and order are NOT
  /// in here: they are the family key the provider is scoped by, so a filter
  /// can narrow the slice but never rewrite it.
  final ProductQuery query;

  /// How many matching rows the list currently reveals — grows by
  /// [productsPageSize] per [InventoryScopeController.showMore].
  final int visibleCount;
}

final inventoryScopeControllerProvider = NotifierProvider.family<
    InventoryScopeController, InventoryScopeState, InventoryScope>(
  InventoryScopeController.new,
);

/// The inventory scope list's ViewModel: the scope decides WHICH rows and in
/// what order, this controller carries the shopkeeper's search text and page,
/// and the derivation between them is memoized.
///
/// Like every list ViewModel it performs NO I/O — the rows come from
/// `ProductsController` — so each method is a synchronous, testable state
/// transition.
class InventoryScopeController extends Notifier<InventoryScopeState> {
  /// The scope this controller manages — the provider family's key, handed to
  /// the constructor by Riverpod (Riverpod 3 passes the family argument to the
  /// notifier's constructor; see `NotifierProvider.family`).
  InventoryScopeController(this.arg);

  /// The scope (one provider per scope: four scope routes stay alive side by
  /// side in the shell's indexed stack).
  final InventoryScope arg;

  /// The "apply the query to the catalog" derivation, kept cheap across
  /// keystrokes and rebuilds (see [ProductQueryCache]).
  final ProductQueryCache _rows = ProductQueryCache();

  @override
  InventoryScopeState build() => const InventoryScopeState();

  /// True when the scope's OWN query already pins the stock slice (the low /
  /// out-of-stock / discontinued screens). The stock chips and any stock
  /// facet are hidden there — a second stock answer could only contradict
  /// the one this screen exists to show.
  bool get pinsStock => arg.query.stock != ProductQuery.stockAll;

  /// The scope's question, narrowed by the shopkeeper's facets and search —
  /// THE predictability contract:
  ///
  ///  1. The scope's slice and order are IDENTITY: they come from [arg],
  ///     are never user-editable and are never dropped by [clear].
  ///  2. Search and the facet set come from [state.query]; a facet the scope
  ///     already pins (stock on a pinned slice) is IGNORED rather than
  ///     intersected, so the screen can never drift from the dashboard
  ///     counter it mirrors.
  ///  3. Everything the shopkeeper added is dropped together by [clear] —
  ///     no half-cleared leftovers.
  ProductQuery get query {
    final user = state.query;
    final merged = arg.query
        .withSearch(user.search)
        .withFilters(
          availability: user.availability,
          category: user.category,
          brand: user.brand,
          minPrice: user.minPrice,
          maxPrice: user.maxPrice,
          recentlyUpdated: user.recentlyUpdated,
          freshness: user.freshness,
        );
    return pinsStock ? merged : merged.withStock(user.stock);
  }

  /// The page this scope should render right now for [items].
  ProductPage pageFor(List<ShopProductItem> items) => ProductPage.of(
        matching(items),
        total: items.length,
        visibleCount: state.visibleCount,
      );

  /// Every row of [items] this scope keeps, in the scope's order, narrowed by
  /// the search text. Memoized against the (catalog, query) pair.
  List<ShopProductItem> matching(List<ShopProductItem> items) =>
      _rows.rows(items, query);

  /// Narrows by typed text.
  void setSearch(String value) => _setQuery(state.query.withSearch(value));

  /// Narrows to one stock scope from the quick chips. Meaningful only when
  /// [pinsStock] is false — the merge ignores it otherwise.
  void setStock(String scope) => _setQuery(state.query.withStock(scope));

  /// Applies the filter sheet's result. The sheet is handed the live USER
  /// query and returns it with only the facets it owns replaced, so the
  /// search text, the stock chips and the scope's slice survive untouched.
  void setFilters(ProductQuery query) => _setQuery(query);

  /// Drops everything the SHOPKEEPER added — the search text and every
  /// filter facet. The SLICE cannot be cleared: it is the screen's identity,
  /// not a filter the shopkeeper applied.
  void clear() => _setQuery(const ProductQuery());

  /// Reveals the next page of the current slice.
  ///
  /// Safe to call at the end of the list: the window is clamped by the number
  /// of matching rows, so an over-wide window renders exactly the same page.
  void showMore() => state = InventoryScopeState(
        query: state.query,
        visibleCount: state.visibleCount + productsPageSize,
      );

  void _setQuery(ProductQuery query) {
    if (query == state.query) return;
    // A new question means a new result set: page from the top again.
    state = InventoryScopeState(query: query);
  }
}
