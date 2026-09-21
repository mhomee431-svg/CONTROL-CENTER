import '../../products/domain/product_query.dart';

/// Which slice of the shop's inventory an [InventoryScopeScreen] shows.
///
/// Lives in the domain (not the screen) because the slice is a QUERY, not UI:
/// the inventory scope's view controller needs it to answer "which rows", and
/// the router needs it to name the four routes — without either of them
/// importing a screen.
enum InventoryScope {
  all,
  low,
  outOfStock,
  discontinued,
  freshness;

  String get title => switch (this) {
        all => 'Inventory list',
        low => 'Low stock',
        outOfStock => 'Out of stock',
        discontinued => 'Discontinued',
        freshness => 'Inventory freshness',
      };

  String get emptyCopy => switch (this) {
        all =>
          'No products yet. Add your first product or import them from Excel.',
        low => 'Nothing is running low. Every product is comfortably stocked.',
        outOfStock => 'Nothing is out of stock. Great job staying on top of it.',
        discontinued =>
          'No discontinued listings. Everything you stock is still active.',
        freshness =>
          'Every listing has been updated recently. Nothing needs attention.',
      };

  /// True when rows must also show their freshness (the freshness route).
  bool get showsFreshness => this == freshness;

  /// The product query this scope IS.
  ///
  /// `all` shows every row in the server's order; `low`, `outOfStock` and
  /// `discontinued` mirror ONE server field each, so the list lines up 1:1 with
  /// the counters the dashboard shows — and `freshness` keeps everything, with
  /// what needs attention first. The search text is the shopkeeper's own, so it
  /// is not part of this query; the scope's view controller adds it.
  ///
  /// Consequence worth knowing: a discontinued listing still appears in `low`
  /// and `outOfStock` when the server reports that stock state for it — those
  /// slices answer "what does the server say about stock", not "what did the
  /// shopkeeper retire".
  ProductQuery get query => switch (this) {
        all => const ProductQuery(sort: ProductSort.asListed),
        low => const ProductQuery(
            stock: ProductQuery.stockServerLow,
            sort: ProductSort.asListed,
          ),
        outOfStock => const ProductQuery(
            stock: ProductQuery.stockOutOfStock,
            sort: ProductSort.asListed,
          ),
        discontinued => const ProductQuery(
            stock: ProductQuery.stockDiscontinued,
            sort: ProductSort.asListed,
          ),
        freshness => const ProductQuery(sort: ProductSort.freshness),
      };
}
