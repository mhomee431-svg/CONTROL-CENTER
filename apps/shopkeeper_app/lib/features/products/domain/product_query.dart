import 'product_models.dart';
import 'product_search.dart';

/// How a catalog list orders the rows it shows.
enum ProductSort {
  /// The server's own order, untouched — the inventory and price lists read
  /// the catalog the way the backend ranked it.
  asListed,

  name,
  price,
  stock,

  /// Newest inventory update first (the products list's default).
  recentlyUpdated,

  /// What needs attention first: stale listings before fresh ones, then the
  /// oldest update — the inventory freshness view's order.
  freshness,
}

/// The ONE query a catalog list applies: search + filters + sort.
///
/// These three are facets of a single question — "which rows does the
/// shopkeeper want to see, and in what order?" — so they live in ONE immutable
/// value object instead of scattered flags. A query therefore cannot contradict
/// itself: there is no way to be filtered by "Out of stock" while claiming to
/// show everything, and the object doubles as a memo key (it compares by
/// value), which is what lets a list re-derive its rows only when the question
/// actually changed.
///
/// The stock scope vocabulary is the CLIENT's own: `low_stock` deliberately
/// spans the server's LOW_STOCK and LIMITED_STOCK rows, because "low" is a
/// picker choice, not a server status. Everything else (the availability
/// boolean, category/brand names, price bounds) is used verbatim — this class
/// never re-derives a fact the backend owns.
class ProductQuery {
  const ProductQuery({
    this.search = '',
    this.stock = stockAll,
    this.availability,
    this.category,
    this.brand,
    this.minPrice,
    this.maxPrice,
    this.recentlyUpdated = false,
    this.sort = ProductSort.recentlyUpdated,
  });

  /// No stock narrowing — the scope every list starts from.
  static const stockAll = 'all';

  /// Exactly the server's IN_STOCK rows.
  static const stockInStock = 'in_stock';

  /// The server's LOW_STOCK **and** LIMITED_STOCK rows.
  ///
  /// The app's "low" concept: `StockStateView.of('LIMITED_STOCK')` reports
  /// [StockStateView.lowStock], so both server states answer "is this low?"
  /// the same way here.
  static const stockLow = 'low_stock';

  /// ONLY the server's raw `LOW_STOCK` rows.
  ///
  /// The inventory scope list mirrors one server counter each, so it asks the
  /// narrowest possible question and lines up 1:1 with the dashboard's
  /// "Low stock" number. (That is the only difference from [stockLow].)
  static const stockServerLow = 'server_low';

  /// Exactly the server's OUT_OF_STOCK rows.
  static const stockOutOfStock = 'out_of_stock';

  /// Listings the shopkeeper (or the platform) discontinued.
  ///
  /// `DISCONTINUED` is a `ShopProduct.status`, NOT a stock state — see
  /// [ShopProductItem.isDiscontinued] — so this slice is the only place those
  /// rows are separated out.
  static const stockDiscontinued = 'discontinued';

  /// Free text matched against name, brand, SKU and variant (see
  /// [ProductSearch]). A blank string filters nothing.
  final String search;

  /// One of [stockAll], [stockInStock], [stockLow], [stockOutOfStock].
  final String stock;

  /// `true` = only available listings, `false` = only unavailable ones,
  /// `null` = both.
  final bool? availability;

  /// Category NAME as the catalog reports it (`null` = any).
  final String? category;

  /// Brand NAME as the catalog reports it (`null` = any).
  final String? brand;

  final double? minPrice;
  final double? maxPrice;

  /// When true, rows the server has never timestamped are dropped — the tile
  /// says "recently updated", so a row with no update cannot satisfy it.
  final bool recentlyUpdated;

  final ProductSort sort;

  /// True when a FILTER narrows the catalog (search is reported separately, so
  /// "Clear filters" never claims to clear a search box it does not own).
  bool get hasActiveFilters =>
      stock != stockAll ||
      availability != null ||
      category != null ||
      brand != null ||
      minPrice != null ||
      maxPrice != null ||
      recentlyUpdated;

  /// True when the search box has usable text.
  bool get hasSearch => search.trim().isNotEmpty;

  /// True when anything at all narrows the catalog.
  bool get isNarrowed => hasActiveFilters || hasSearch;

  /// A copy with [value] as the search text.
  ProductQuery withSearch(String value) => ProductQuery(
    search: value,
    stock: stock,
    availability: availability,
    category: category,
    brand: brand,
    minPrice: minPrice,
    maxPrice: maxPrice,
    recentlyUpdated: recentlyUpdated,
    sort: sort,
  );

  /// A copy narrowed to one stock scope.
  ProductQuery withStock(String scope) => ProductQuery(
    search: search,
    stock: scope,
    availability: availability,
    category: category,
    brand: brand,
    minPrice: minPrice,
    maxPrice: maxPrice,
    recentlyUpdated: recentlyUpdated,
    sort: sort,
  );

  /// A copy ordered by [value].
  ProductQuery withSort(ProductSort value) => ProductQuery(
    search: search,
    stock: stock,
    availability: availability,
    category: category,
    brand: brand,
    minPrice: minPrice,
    maxPrice: maxPrice,
    recentlyUpdated: recentlyUpdated,
    sort: value,
  );

  /// Replaces the filter-only facets in ONE step.
  ///
  /// Every facet is required (and a `null` argument CLEARS it), which is why
  /// this is not a `copyWith`: `copyWith` reads `null` as "keep the previous
  /// value", so clearing Availability — or Reset — would silently be a no-op.
  /// Search, stock scope and sort are carried over untouched because they are
  /// edited outside the filter sheet.
  ProductQuery withFilters({
    required bool? availability,
    required String? category,
    required String? brand,
    required double? minPrice,
    required double? maxPrice,
    required bool recentlyUpdated,
  }) => ProductQuery(
    search: search,
    stock: stock,
    availability: availability,
    category: category,
    brand: brand,
    minPrice: minPrice,
    maxPrice: maxPrice,
    recentlyUpdated: recentlyUpdated,
    sort: sort,
  );

  /// Drops every filter, keeping the search text, the scope and the sort.
  ProductQuery clearFilters() => withFilters(
    availability: null,
    category: null,
    brand: null,
    minPrice: null,
    maxPrice: null,
    recentlyUpdated: false,
  );

  /// The rows of [items] this query keeps, in the order it asks for.
  ///
  /// [index] is the pre-built [ProductSearch] over the same rows — passed in
  /// (rather than built here) so a keystroke costs one `contains` per row
  /// instead of a full re-index of the catalog.
  List<ShopProductItem> apply(
    List<ShopProductItem> items,
    ProductSearch index,
  ) {
    final rows = items
        .where((item) {
          if (!index.matches(item, search)) return false;

          switch (stock) {
            case stockInStock:
              if (item.stockStatus != 'IN_STOCK') return false;
            case stockLow:
              if (item.stockStatus != 'LOW_STOCK' &&
                  item.stockStatus != 'LIMITED_STOCK') {
                return false;
              }
            case stockServerLow:
              if (item.stockStatus != 'LOW_STOCK') return false;
            case stockOutOfStock:
              if (item.stockStatus != 'OUT_OF_STOCK') return false;
            case stockDiscontinued:
              if (!item.isDiscontinued) return false;
          }

          if (availability != null && item.isAvailable != availability) {
            return false;
          }
          if (category != null && item.category != category) return false;
          if (brand != null && item.brand != brand) return false;
          if (minPrice != null && item.price < minPrice!) return false;
          if (maxPrice != null && item.price > maxPrice!) return false;
          if (recentlyUpdated && item.lastUpdated == null) return false;
          return true;
        })
        .toList(growable: false);

    switch (sort) {
      // The server's own order is already the row order — nothing to do.
      case ProductSort.asListed:
        break;
      case ProductSort.name:
        rows.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case ProductSort.price:
        rows.sort((a, b) => a.price.compareTo(b.price));
      case ProductSort.stock:
        rows.sort((a, b) => b.quantity.compareTo(a.quantity));
      case ProductSort.recentlyUpdated:
        rows.sort((a, b) {
          final ta = a.lastUpdated ?? DateTime.fromMillisecondsSinceEpoch(0);
          final tb = b.lastUpdated ?? DateTime.fromMillisecondsSinceEpoch(0);
          return tb.compareTo(ta);
        });
      case ProductSort.freshness:
        // Stale first (they are the ones that need a touch), then the oldest
        // update — a listing the server never timestamped sorts as oldest.
        rows.sort((a, b) {
          final aStale = a.isStale ? 0 : 1;
          final bStale = b.isStale ? 0 : 1;
          if (aStale != bStale) return aStale.compareTo(bStale);
          final aDate = a.lastUpdated ?? DateTime(1970);
          final bDate = b.lastUpdated ?? DateTime(1970);
          return aDate.compareTo(bDate);
        });
    }
    return rows;
  }

  @override
  bool operator ==(Object other) =>
      other is ProductQuery &&
      other.search == search &&
      other.stock == stock &&
      other.availability == availability &&
      other.category == category &&
      other.brand == brand &&
      other.minPrice == minPrice &&
      other.maxPrice == maxPrice &&
      other.recentlyUpdated == recentlyUpdated &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(
    search,
    stock,
    availability,
    category,
    brand,
    minPrice,
    maxPrice,
    recentlyUpdated,
    sort,
  );
}

/// Memoized "apply this query to that catalog" — the derivation every
/// catalog-backed list performs.
///
/// A screen re-derives its rows on every rebuild, and the shopkeeper re-types
/// their search on every keystroke: this keeps both cheap. The [ProductSearch]
/// index is built once per catalog INSTANCE (a keystroke re-runs `contains`,
/// never a re-index), and the last result is reused when neither the rows nor
/// the query changed — so a snackbar, an availability flip or a page turn costs
/// nothing.
class ProductQueryCache {
  final ProductSearchCache _index = ProductSearchCache();
  List<ShopProductItem>? _rows;
  List<ShopProductItem>? _source;
  ProductQuery? _query;

  /// The rows of [items] that [query] keeps, in the query's order.
  List<ShopProductItem> rows(
    List<ShopProductItem> items,
    ProductQuery query,
  ) {
    if (identical(_source, items) && _query == query) return _rows!;
    final derived = query.apply(items, _index.of(items));
    _source = items;
    _query = query;
    _rows = derived;
    return derived;
  }
}

