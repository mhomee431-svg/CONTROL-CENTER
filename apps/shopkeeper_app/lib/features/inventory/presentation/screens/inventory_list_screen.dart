import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/state/system_state_view.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/cached_data_notice.dart';
import '../../../../core/ui/debounced_search_field.dart';
import '../../../../core/ui/filter_ui.dart';
import '../../../../core/ui/lazy_list.dart';
import '../../../../core/ui/load_more.dart';
import '../../../products/domain/product_models.dart';
import '../../../products/domain/product_query.dart';
import '../../../products/presentation/controllers/products_controller.dart';
import '../../../products/presentation/controllers/recent_searches_controller.dart';
import '../../domain/inventory_scope.dart';
import '../controllers/inventory_scope_controller.dart';
import '../widgets/inventory_filter_sheet.dart';
import '../widgets/inventory_shared.dart';

/// Inventory List / Low Stock / Out of Stock / Discontinued / Inventory
/// Freshness.
///
/// One implementation, five routes: [scope] picks the slice — and with it the
/// question the list asks (`scope.query`), so a slice is a query, not a block
/// of filter code in the screen. The shopkeeper's OWN state (the search text
/// and the page) lives in the scope's view controller, which is why leaving
/// this screen and coming back keeps both. Rows always show the server stock
/// state; the freshness route also surfaces last-updated times so the
/// shopkeeper can see what to touch next.
class InventoryScopeScreen extends ConsumerStatefulWidget {
  const InventoryScopeScreen({super.key, required this.scope});

  final InventoryScope scope;

  @override
  ConsumerState<InventoryScopeScreen> createState() =>
      _InventoryScopeScreenState();
}

class _InventoryScopeScreenState extends ConsumerState<InventoryScopeScreen> {
  /// The query lives in the scope's view controller;
  /// [DebouncedSearchField] mirrors it internally, seeded from the query on
  /// mount, which is what brings the shopkeeper's search text back with the
  /// screen.

  InventoryScopeController get _controller =>
      ref.read(inventoryScopeControllerProvider(widget.scope).notifier);

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

  /// Opens the filter sheet (Category / Freshness). The sheet gets the USER
  /// query and hands it back with only its own facets replaced — search,
  /// stock chips and the scope's slice ride along untouched.
  void _openFilters() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => InventoryFilterSheet(
        initial:
            ref.read(inventoryScopeControllerProvider(widget.scope)).query,
        categories: distinctFilterValues(
          ref.read(productsControllerProvider).items,
          (item) => item.category,
        ),
        onApply: (applied) => ref
            .read(inventoryScopeControllerProvider(widget.scope).notifier)
            .setFilters(applied),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(productsControllerProvider);
    // The view state is watched (a keystroke rebuilds the list), the page is
    // derived from the catalog rows + the scope's question + the search text,
    // and memoized inside the controller: a rebuild that changed none of them
    // re-runs neither the predicate nor the sort.
    final view = ref.watch(inventoryScopeControllerProvider(widget.scope));
    final page = ref
        .watch(inventoryScopeControllerProvider(widget.scope).notifier)
        .pageFor(catalog.items);
    final query = view.query;
    // Shared product-search history: submitted terms only, most-recent-first.
    final recents = ref.watch(recentSearchesControllerProvider).terms;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.scope.title),
        actions: [
          if (catalog.status == ProductsStatus.ready)
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: 'Refresh',
              onPressed: () =>
                  ref.read(productsControllerProvider.notifier).load(),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: DebouncedSearchField(
              key: const Key('inventory-search-field'),
              hintText: 'Search name, brand or SKU',
              initialValue: query.search,
              onChanged: _controller.setSearch,
              // A submitted term is history (shared across the catalog lists).
              onSubmitted: (value) => ref
                  .read(recentSearchesControllerProvider.notifier)
                  .record(value),
              onFocusLost: (value) => ref
                  .read(recentSearchesControllerProvider.notifier)
                  .record(value),
              recentSearches: recents,
              onRecentSelected: _controller.setSearch,
              onRecentRemoved: (term) => ref
                  .read(recentSearchesControllerProvider.notifier)
                  .remove(term),
            ),
          ),
          // Quick STOCK facets — the same chips as the products list. Hidden
          // on the low / out / discontinued slices: their query already pins
          // the stock answer, so a second stock facet could only contradict
          // it (the sheet hides its stock section for the same reason).
          if (catalog.status == ProductsStatus.ready && !_controller.pinsStock)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: FilterChipBar<String>(
                options: const [
                  FilterChoice(label: 'All', value: ProductQuery.stockAll),
                  FilterChoice(
                    label: 'In Stock',
                    value: ProductQuery.stockInStock,
                  ),
                  FilterChoice(
                    label: 'Low Stock',
                    value: ProductQuery.stockLow,
                  ),
                  FilterChoice(
                    label: 'Out of Stock',
                    value: ProductQuery.stockOutOfStock,
                  ),
                ],
                selected: query.stock,
                onSelected: _controller.setStock,
              ),
            ),
          // Counter + Clear + Filters: what the list currently answers, and
          // the two ways to change the question. The Clear button and the
          // icon tint track the facets the SHOPKEEPER applied — the scope's
          // own slice never lights them up, because it cannot be cleared.
          if (catalog.status == ProductsStatus.ready)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${page.matched} of ${page.total} products',
                      key: const Key('inventory-count'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                  if (query.hasActiveFilters)
                    TextButton.icon(
                      key: const Key('inventory-clear-filters'),
                      onPressed: _controller.clear,
                      icon: const Icon(
                        Icons.filter_alt_off_outlined,
                        size: 18,
                      ),
                      label: const Text('Clear'),
                    ),
                  IconButton(
                    key: const Key('inventory-filters-button'),
                    tooltip: 'Filters',
                    onPressed: _openFilters,
                    icon: Icon(
                      Icons.filter_alt_outlined,
                      color: query.hasActiveFilters
                          ? AppTheme.brandSeed
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ProductsAsyncBody(
              status: catalog.status,
              message: catalog.message,
              onRetry: () =>
                  ref.read(productsControllerProvider.notifier).load(),
              // Pull is the SILENT path (see ProductsController.refresh): the
              // rows stay on screen while fresh ones load; the app-bar icon
              // above keeps the loud spinner.
              onRefresh: () =>
                  ref.read(productsControllerProvider.notifier).refresh(),
              builder: (context) => LazyListView(
                // Always scrollable so the gesture works even on a scope with
                // no rows (its empty state fills the viewport).
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: page.rows.length,
                // Provenance first: a cached list that looks live is worse
                // than no list at all.
                header: [
                  if (catalog.fromCache) const CachedDataNotice(),
                ],
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 16),
                itemBuilder: (context, i) => _ProductRow(
                  item: page.rows[i],
                  showFreshness: widget.scope.showsFreshness,
                  onTap: () => context.push(
                    Routes.updateStock,
                    extra: page.rows[i],
                  ),
                ),
                // The page break: only a slice bigger than one page ever
                // shows it, and it names how many rows are still behind it.
                footer: [
                  if (page.hasMore)
                    LoadMoreTile(
                      key: const Key('inventory-load-more'),
                      hidden: page.hidden,
                      onTap: _controller.showMore,
                    ),
                ],
                // The rows are built lazily; the filter-miss / empty-catalog
                // copy stays with the feature.
                emptyPlaceholder: _EmptyScope(
                  scope: widget.scope,
                  query: query,
                  catalogIsEmpty: page.isEmptyCatalog,
                  onClear: _controller.clear,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyScope extends StatelessWidget {
  const _EmptyScope({
    required this.scope,
    required this.query,
    required this.catalogIsEmpty,
    required this.onClear,
  });

  final InventoryScope scope;

  /// The shopkeeper's OWN question (search text + filter facets) — the
  /// slice itself is never the reason a non-empty catalog shows no rows.
  final ProductQuery query;

  /// True when the shop has no listings at all, not merely no visible ones.
  final bool catalogIsEmpty;

  /// Clears the search text AND every filter facet (never the scope's slice).
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    // Three distinct explanations: an empty catalog, a search that matched
    // nothing, and a filter that matched nothing — each keeps its own copy,
    // and both no-match branches hand over the one clear action.
    if (!catalogIsEmpty) {
      if (query.hasSearch) {
        return SystemStateView.empty(
          title: 'No products match your search',
          icon: Icons.search_off_outlined,
          iconColor: outline,
          action: OutlinedButton(
            onPressed: onClear,
            child: const Text('Clear search'),
          ),
        );
      }
      if (query.hasActiveFilters) {
        return SystemStateView.empty(
          title: 'No products match your filters',
          icon: Icons.filter_alt_off_outlined,
          iconColor: outline,
          action: OutlinedButton(
            onPressed: onClear,
            child: const Text('Clear filters'),
          ),
        );
      }
    }
    return SystemStateView.empty(
      title: scope.emptyCopy,
      icon: Icons.inventory_2_outlined,
      iconColor: outline,
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.item,
    required this.showFreshness,
    this.onTap,
  });

  final ShopProductItem item;
  final bool showFreshness;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final stock = item.stockState;
    return ListTile(
      onTap: onTap,
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            '${item.quantity} units · ${moneyLabel(item.price)}',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              InfoChip(label: stock.label, color: stockStateColor(stock)),
              if (showFreshness)
                InfoChip(
                  label: freshnessChipLabel(
                    item.freshnessStatus,
                    item.lastUpdated,
                  ),
                  color: freshnessColor(item.freshnessStatus),
                )
              else
                InfoChip(
                  label: inventorySourceLabel(item.source),
                  color: inventorySourceColor(item.source),
                  icon: inventorySourceIcon(item.source),
                ),
            ],
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}
