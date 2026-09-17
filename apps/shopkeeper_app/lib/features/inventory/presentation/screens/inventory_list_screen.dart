import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/state/system_state_view.dart';
import '../../../../core/ui/lazy_list.dart';
import '../../../products/domain/product_models.dart';
import '../../../products/domain/product_search.dart';
import '../../../products/presentation/controllers/products_controller.dart';
import '../widgets/inventory_shared.dart';

/// Which slice of the inventory a [InventoryScopeScreen] shows.
enum InventoryScope {
  all,
  low,
  outOfStock,
  freshness;

  String get title => switch (this) {
        all => 'Inventory list',
        low => 'Low stock',
        outOfStock => 'Out of stock',
        freshness => 'Inventory freshness',
      };

  String get emptyCopy => switch (this) {
        all =>
          'No products yet. Add your first product or import them from Excel.',
        low => 'Nothing is running low. Every product is comfortably stocked.',
        outOfStock => 'Nothing is out of stock. Great job staying on top of it.',
        freshness =>
          'Every listing has been updated recently. Nothing needs attention.',
      };
}

/// Inventory List / Low Stock / Out of Stock / Inventory Freshness.
///
/// One implementation, four routes: [scope] picks the slice. Rows always show
/// the server stock state; the freshness route also surfaces last-updated
/// times so the shopkeeper can see what to touch next.
class InventoryScopeScreen extends ConsumerStatefulWidget {
  const InventoryScopeScreen({super.key, required this.scope});

  final InventoryScope scope;

  @override
  ConsumerState<InventoryScopeScreen> createState() =>
      _InventoryScopeScreenState();
}

class _InventoryScopeScreenState extends ConsumerState<InventoryScopeScreen> {
  String _query = '';

  /// The catalog's searchable text, indexed once per load — see [ProductSearch].
  final ProductSearchCache _searchIndex = ProductSearchCache();

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

  List<ShopProductItem> _filtered(List<ShopProductItem> items) {
    // The predicate is the app's ONE product search (name / brand / SKU /
    // variant), indexed once per catalog: a keystroke costs one `contains` per
    // row, not four lower-cased strings per row.
    final search = _searchIndex.of(items);
    bool matches(ShopProductItem i) => search.matches(i, _query);

    return switch (widget.scope) {
      InventoryScope.all => items.where(matches).toList(),
      InventoryScope.low =>
        items.where((i) => i.isLowStock && matches(i)).toList(),
      InventoryScope.outOfStock =>
        items.where((i) => i.isOutOfStock && matches(i)).toList(),
      // Freshness view: everything, stale listings first.
      InventoryScope.freshness =>
        items.where(matches).toList()
          ..sort((a, b) {
            final aStale = a.isStale ? 0 : 1;
            final bStale = b.isStale ? 0 : 1;
            if (aStale != bStale) return aStale.compareTo(bStale);
            final aDate = a.lastUpdated ?? DateTime(1970);
            final bDate = b.lastUpdated ?? DateTime(1970);
            return aDate.compareTo(bDate); // oldest first
          }),
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(productsControllerProvider);
    final visible = _filtered(state.items);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.scope.title),
        actions: [
          if (state.status == ProductsStatus.ready)
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
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search name, brand or SKU',
                prefixIcon: const Icon(Icons.search_outlined),
                isDense: true,
              ),
            ),
          ),
          if (state.status == ProductsStatus.ready)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${visible.length} of ${state.items.length} products',
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
              status: state.status,
              message: state.message,
              onRetry: () => ref.read(productsControllerProvider.notifier).load(),
              builder: (context) => LazyListView(
                itemCount: visible.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 16),
                itemBuilder: (context, i) => _ProductRow(
                  item: visible[i],
                  showFreshness: widget.scope == InventoryScope.freshness,
                  onTap: () => context.push(
                    Routes.updateStock,
                    extra: visible[i],
                  ),
                ),
                // The rows are built lazily; the filter-miss / empty-catalog
                // copy stays with the feature.
                emptyPlaceholder: _EmptyScope(
                  scope: widget.scope,
                  query: _query,
                  onClearSearch: () => setState(() => _query = ''),
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
    final stock = StockStateView.of(item.stockStatus);
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
