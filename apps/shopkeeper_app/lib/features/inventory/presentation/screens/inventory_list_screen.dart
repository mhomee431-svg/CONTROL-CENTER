import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/state/system_state_view.dart';
import '../../../../core/ui/cached_data_notice.dart';
import '../../../../core/ui/lazy_list.dart';
import '../../../../core/ui/load_more.dart';
import '../../../products/domain/product_models.dart';
import '../../../products/presentation/controllers/products_controller.dart';
import '../../domain/inventory_scope.dart';
import '../controllers/inventory_scope_controller.dart';
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
  /// The search box's text buffer. The query itself lives in the scope's view
  /// controller; this controller only mirrors it so typing keeps its cursor
  /// and selection, and it is seeded from the query on mount, which is what
  /// brings the shopkeeper's search text back with the screen.
  final TextEditingController _search = TextEditingController();

  /// The state and the controller of THIS scope (one provider per scope: four
  /// scope routes stay alive side by side in the shell's indexed stack).
  InventoryScopeState get _state =>
      ref.read(inventoryScopeControllerProvider(widget.scope));

  InventoryScopeController get _controller =>
      ref.read(inventoryScopeControllerProvider(widget.scope).notifier);

  @override
  void initState() {
    super.initState();
    _search.text = _state.query.search;
    Future.microtask(() {
      final state = ref.read(productsControllerProvider);
      if (state.status == ProductsStatus.loading && state.items.isEmpty) {
        ref.read(productsControllerProvider.notifier).load();
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
            child: TextField(
              key: const Key('inventory-search-field'),
              controller: _search,
              onChanged: _controller.setSearch,
              decoration: InputDecoration(
                hintText: 'Search name, brand or SKU',
                prefixIcon: const Icon(Icons.search_outlined),
                isDense: true,
              ),
            ),
          ),
          if (catalog.status == ProductsStatus.ready)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${page.matched} of ${page.total} products',
                  key: const Key('inventory-count'),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            ),
          Expanded(
            child: ProductsAsyncBody(
              status: catalog.status,
              message: catalog.message,
              onRetry: () =>
                  ref.read(productsControllerProvider.notifier).load(),
              builder: (context) => LazyListView(
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
                  query: query.search,
                  onClearSearch: () {
                    _search.clear();
                    _controller.clear();
                  },
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
    required this.onClearSearch,
  });

  final InventoryScope scope;
  final String query;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    // A filter that matched nothing is different from an empty catalog —
    // each branch keeps its own copy, the layout is the shared empty state.
    if (query.trim().isNotEmpty) {
      return SystemStateView.empty(
        title: 'No products match your search',
        icon: Icons.search_off_outlined,
        iconColor: outline,
        action: OutlinedButton(
          onPressed: onClearSearch,
          child: const Text('Clear search'),
        ),
      );
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
                  label:
                      '${freshnessLabel(item.freshnessStatus)} · ${lastUpdatedLabel(item.lastUpdated)}',
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
