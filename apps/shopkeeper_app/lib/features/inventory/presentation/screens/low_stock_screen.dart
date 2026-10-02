import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/state/system_state_view.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/debounced_search_field.dart';
import '../../../../core/ui/lazy_list.dart';
import '../../../products/domain/product_models.dart';
import '../../../products/presentation/controllers/products_controller.dart';
import '../../../products/presentation/controllers/recent_searches_controller.dart';
import '../../../products/presentation/widgets/product_details_sheet.dart';
import '../../../products/presentation/widgets/product_image_view.dart';
import '../../../products/presentation/widgets/stock_sheets.dart';
import '../widgets/inventory_shared.dart';

/// Dedicated Low Stock Management screen — the restock workbench.
///
/// Lists every product whose **current stock is at or below its own low-stock
/// threshold** (server rule: `quantity <= low_stock_threshold`), ordered by
/// urgency (fewest units left first), with two actions per card:
///   - **Update Stock** — quick delta sheet, no page reload;
///   - **Open Product** — the full read-only details view.
///
/// The warning banner appears only when something actually needs restocking;
/// an empty state reads "All items well stocked". The controller is shared
/// with the inventory list, so a restock lands everywhere at once.
class LowStockScreen extends ConsumerStatefulWidget {
  const LowStockScreen({super.key});

  @override
  ConsumerState<LowStockScreen> createState() => _LowStockScreenState();
}

class _LowStockScreenState extends ConsumerState<LowStockScreen> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final state = ref.read(productsControllerProvider);
      if (state.status == ProductsStatus.loading && state.items.isEmpty) {
        ref.read(productsControllerProvider.notifier).load();
      }
    });
  }

  /// Restock list: only listings at/below their own threshold, ordered by
  /// urgency (fewest units first), optionally narrowed by the search field.
  ///
  /// Memoized on the (catalog, query) pair — the same rule
  /// `ProductQueryCache` applies to the other catalog lists. `build()` runs on
  /// every rebuild (a snackbar, an availability flip, a page turn, the text
  /// field's own rebuilds), and the sort is O(n log n) over the WHOLE catalog;
  /// without this every one of those rebuilds re-sorted a list the shopkeeper
  /// never asked to change.
  List<ShopProductItem> _restock(List<ShopProductItem> items) {
    final source = items;
    if (identical(_restockSource, source) && _restockQuery == _query) {
      return _restockRows!;
    }
    final derived = _deriveRestock(items);
    _restockSource = source;
    _restockQuery = _query;
    _restockRows = derived;
    return derived;
  }

  List<ShopProductItem>? _restockRows;
  List<ShopProductItem>? _restockSource;
  String? _restockQuery;

  List<ShopProductItem> _deriveRestock(List<ShopProductItem> items) {
    final needsRestock = items
        .where((i) => !i.isDiscontinued && i.quantity <= _thresholdOf(i))
        .toList()
      ..sort((a, b) => a.quantity.compareTo(b.quantity));
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return needsRestock;
    return needsRestock
        .where((i) =>
            i.name.toLowerCase().contains(query) ||
            (i.sku ?? '').toLowerCase().contains(query))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(productsControllerProvider);
    final restock = _restock(state.items);
    // Shared search history, so a term typed on one catalog list is offered on
    // the others too.
    final recents = ref.watch(recentSearchesControllerProvider).terms;

    return Scaffold(
      appBar: AppBar(title: Text(appText(context).commonLowStock3)),
      floatingActionButton: state.status == ProductsStatus.ready
          ? FloatingActionButton.extended(
              heroTag: 'low-stock-refresh',
              onPressed: () =>
                  ref.read(productsControllerProvider.notifier).load(),
              icon: const Icon(Icons.refresh_outlined),
              label: Text(appText(context).commonRefresh3),
            )
          : null,
      body: ProductsAsyncBody(
        status: state.status,
        message: state.message,
        onRetry: () => ref.read(productsControllerProvider.notifier).load(),
        // Pull is the silent path: the restock cards stay on screen while the
        // fresh catalog loads (the FAB above keeps the loud spinner).
        onRefresh: () =>
            ref.read(productsControllerProvider.notifier).refresh(),
        builder: (context) => Column(
          children: [
            // Warning banner — only when something actually needs restocking.
            if (restock.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: _RestockBanner(count: restock.length),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              // The shared debounced field, as on every other catalog list: the
              // restock slice is derived from the whole catalog, so filtering it
              // on every glyph would re-run a full pass per keystroke. The
              // field owns its text controller, so the value survives the
              // setState rebuilds below.
              child: DebouncedSearchField(
                key: const Key('low-stock-search-field'),
                hintText: appText(context).commonSearchNameOrSKU,
                initialValue: _query,
                onChanged: (value) => setState(() => _query = value),
                // A submitted term is history (shared across the catalog lists).
                onSubmitted: (value) => ref
                    .read(recentSearchesControllerProvider.notifier)
                    .record(value),
                onFocusLost: (value) => ref
                    .read(recentSearchesControllerProvider.notifier)
                    .record(value),
                recentSearches: recents,
                onRecentSelected: (value) => setState(() => _query = value),
                onRecentRemoved: (term) => ref
                    .read(recentSearchesControllerProvider.notifier)
                    .remove(term),
              ),
            ),
            Expanded(
              // ONE lazy list for the rows and the empty state: with
              // AlwaysScrollable physics the pull gesture works even when a
              // full shelf leaves nothing to scroll.
              child: LazyListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: restock.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 16),
                itemBuilder: (context, i) => _RestockCard(
                  item: restock[i],
                  onUpdateStock: () => _openStockSheet(context, restock[i]),
                  onOpenProduct: () => _openDetails(context, restock[i]),
                ),
                emptyPlaceholder: _WellStockedView(query: _query),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openStockSheet(BuildContext context, ShopProductItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StockUpdateSheet(item: item),
    );
  }

  void _openDetails(BuildContext context, ShopProductItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ProductDetailsSheet(item: item),
    );
  }

  /// The per-listing threshold the shopkeeper set. The server value wins; the
  /// platform default of 5 (the backend's own create default) applies when an
  /// older payload did not carry one.
  int _thresholdOf(ShopProductItem item) => item.lowStockThreshold ?? 5;
}

/// Amber warning shown only when `count > 0` — never rendered for an empty
/// list, so a healthy inventory never looks like an alarm.
class _RestockBanner extends StatelessWidget {
  const _RestockBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('low-stock-banner'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.pendingAmber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.pendingAmber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppTheme.pendingAmber),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              appText(context).lowStockScreenCountItemValueImmediateRestocking(count, count == 1 ? ' requires' : 's require'),
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: AppTheme.pendingAmber),
            ),
          ),
        ],
      ),
    );
  }
}

/// The healthy state — restock list is empty, so the banner is gone and the
/// shopkeeper gets a clear "nothing to do".
class _WellStockedView extends StatelessWidget {
  const _WellStockedView({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    // A search that matched nothing is different from a genuinely full shelf.
    if (query.trim().isNotEmpty) {
      return SystemStateView.empty(
        title: appText(context).lowStockScreenNoRestockNeedsMatchYour,
        icon: Icons.search_off_outlined,
        iconColor: outline,
      );
    }
    return SystemStateView.empty(
      key: const Key('low-stock-empty'),
      title: appText(context).commonAllItemsWellStocked,
      message: appText(context).lowStockScreenNothingIsAtOrBelow,
      icon: Icons.check_circle_outline,
    );
  }
}

/// One restock decision: what, how little is left, and the two actions.
class _RestockCard extends StatelessWidget {
  const _RestockCard({
    required this.item,
    required this.onUpdateStock,
    required this.onOpenProduct,
  });

  final ShopProductItem item;
  final VoidCallback onUpdateStock;
  final VoidCallback onOpenProduct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outline = theme.colorScheme.outline;
    final state = item.stockState;

    return Card(
      key: Key('low-stock-card-${item.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail (falls back to the box icon when the master has
                // no image) — always present, never a broken layout.
                // Shared resilient thumbnail, identical to the products list:
                // a progress state while loading, the same outline box when the
                // presigned URL has expired (instead of a raw framework error
                // box), and a ~2x decode instead of the source resolution — a
                // 48px thumbnail never needs the full-resolution bytes (§110).
                ProductImageView(
                  imageUrl: item.imageUrl,
                  width: 48,
                  height: 48,
                  borderRadius: BorderRadius.circular(8),
                  // The card already shows the name, so the thumbnail is
                  // decorative — announcing "image" here only adds noise.
                  excludeFromSemantics: true,
                  cacheWidth: 96,
                  placeholderWidget: Icon(
                    Icons.inventory_2_outlined,
                    size: 22,
                    color: outline,
                  ),
                  errorWidget: Icon(
                    Icons.inventory_2_outlined,
                    size: 22,
                    color: outline,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (item.sku != null && item.sku!.isNotEmpty)
                        Text(appText(context).lowStockScreenSKUSku('${item.sku}'),
                            style: TextStyle(fontSize: 12, color: outline)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  appText(context).lowStockScreenQuantityUnitsLeft(item.quantity),
                  key: Key('low-stock-qty-${item.id}'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: item.quantity == 0
                        ? AppTheme.rejectedRed
                        : AppTheme.pendingAmber,
                  ),
                ),
                const SizedBox(width: 10),
                Text(appText(context).lowStockScreenThresholdValueUnits(item.lowStockThreshold ?? 5),
                    style: TextStyle(fontSize: 12, color: outline)),
                const Spacer(),
                InfoChip(label: state.label, color: stockStateColor(state)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: Key('low-stock-update-${item.id}'),
                    onPressed: onUpdateStock,
                    icon:
                        const Icon(Icons.add_shopping_cart_outlined, size: 18),
                    label: Text(appText(context).commonUpdateStock),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: Key('low-stock-open-${item.id}'),
                    onPressed: onOpenProduct,
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: Text(appText(context).commonOpenProduct),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
