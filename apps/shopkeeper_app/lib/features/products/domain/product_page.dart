import 'product_models.dart';

/// How many matching rows one page of a catalog-backed list reveals.
///
/// A shop is paged in memory (the whole catalog arrives in ONE `view=list`
/// response), so this is a RENDER window, not a second request: it keeps a
/// list's work proportional to what the shopkeeper is looking at instead of to
/// the size of their catalog, and it gives every list's state a page to
/// advance.
const int productsPageSize = 50;

/// One page of a catalog list, with the counters the screen renders.
///
/// Derived — never stored as separate flags — so "how many matched", "how many
/// are shown" and "is there more" can never contradict each other.
class ProductPage {
  const ProductPage({
    required this.rows,
    required this.matched,
    required this.total,
    required this.hasMore,
  });

  /// Cuts [matched] at [visibleCount].
  ///
  /// The ONE place a page is computed, so the products list, the inventory
  /// scopes and the price list all page identically — including the clamp that
  /// makes an over-wide window harmless.
  factory ProductPage.of(
    List<ShopProductItem> matched, {
    required int total,
    required int visibleCount,
  }) {
    final rows = matched.length <= visibleCount
        ? matched
        : matched.sublist(0, visibleCount);
    return ProductPage(
      rows: rows,
      matched: matched.length,
      total: total,
      hasMore: rows.length < matched.length,
    );
  }

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
