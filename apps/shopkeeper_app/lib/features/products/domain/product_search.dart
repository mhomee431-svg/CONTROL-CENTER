import 'product_models.dart';

/// The ONE product search predicate in the app.
///
/// The products list, the inventory scopes (all / low / out of stock /
/// freshness) and the price list all ask the same question of the same rows —
/// "does this row's human-readable text contain what the shopkeeper typed?" —
/// so the answer lives here instead of being re-implemented per screen. The
/// searched fields are a superset on purpose: name, brand, SKU and variant,
/// because a value printed on Product Details must be searchable.
///
/// Speed: every row is indexed ONCE — its fields trimmed, joined and lowercased
/// a single time — so a keystroke costs one `contains` per row instead of four
/// `toLowerCase()` allocations per row. On a 2,000-row shop that is the
/// difference between a search box that keeps up and one that lags behind the
/// keyboard.
class ProductSearch {
  ProductSearch(Iterable<ShopProductItem> items) {
    for (final item in items) {
      _index[item.id] = (item: item, haystack: _haystack(item));
    }
  }

  /// The row's id → (the row it was built from, its searchable lowercase text).
  final Map<int, ({ShopProductItem item, String haystack})> _index = {};

  /// True when [query] matches [item]. A blank query matches every row — no
  /// text means no filtering, and the screen decides what an empty list means
  /// (empty shop vs. filter that matched nothing).
  bool matches(ShopProductItem item, String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;

    final row = _index[item.id];
    if (row != null && identical(row.item, item)) {
      return row.haystack.contains(needle);
    }

    // A row that changed (or arrived) after the index was built. Rows are
    // immutable, so a changed row is a new instance: index it now and keep it —
    // the fallback then costs nothing on the next keystroke.
    final haystack = _haystack(item);
    _index[item.id] = (item: item, haystack: haystack);
    return haystack.contains(needle);
  }

  /// Fields are joined with a NUL separator so a query can never match across
  /// two fields (a search for "ulmi" must not be satisfied by "Amul" + "Milk").
  static String _haystack(ShopProductItem item) => [
    item.name,
    item.brand ?? '',
    item.sku ?? '',
    item.variant ?? '',
  ].map((part) => part.trim()).join('\u0000').toLowerCase();
}

/// Keeps a [ProductSearch] in step with the catalog list currently on screen.
///
/// A screen calls [of] during build; the index is rebuilt only when the list
/// instance changes (a load, or a write that replaced a row), so filtering on
/// every keystroke never re-indexes a whole catalog.
class ProductSearchCache {
  List<ShopProductItem>? _source;
  ProductSearch _search = ProductSearch(const []);

  ProductSearch of(List<ShopProductItem> items) {
    if (!identical(_source, items)) {
      _search = ProductSearch(items);
      _source = items;
    }
    return _search;
  }
}