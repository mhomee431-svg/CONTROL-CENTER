import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../products/domain/product_models.dart';
import '../../../products/presentation/controllers/products_controller.dart';
import '../widgets/inventory_shared.dart';

/// Inventory Dashboard — the hub of the Inventory module.
///
/// Renders the shop's stock health (server summary counts + freshness) and
/// navigates to every inventory sub-screen: list, low stock, out of stock,
/// freshness, sync status, stock updates and history — plus quick links to
/// the Pricing list and the Import Center.
class InventoryDashboardScreen extends ConsumerStatefulWidget {
  const InventoryDashboardScreen({super.key});

  @override
  ConsumerState<InventoryDashboardScreen> createState() =>
      _InventoryDashboardScreenState();
}

class _InventoryDashboardScreenState
    extends ConsumerState<InventoryDashboardScreen> {
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(productsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Inventory')),
      body: ProductsAsyncBody(
        status: state.status,
        message: state.message,
        onRetry: () => ref.read(productsControllerProvider.notifier).load(),
        builder: (context) =>
            _Dashboard(items: state.items, summary: state.summary),
      ),
    );
  }
}

/// One navigable row of the dashboard hub.
class _HubTile {
  const _HubTile(this.key, this.icon, this.title, this.subtitle, this.route);

  final Key key;
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
}

const List<_HubTile> _stockTiles = [
  _HubTile(
    Key('inventory-tile-list'),
    Icons.list_alt_outlined,
    'Inventory list',
    'Every product with live stock levels',
    Routes.inventoryList,
  ),
  _HubTile(
    Key('inventory-tile-low-stock'),
    Icons.warning_amber_outlined,
    'Low stock',
    'Products running below their threshold',
    Routes.lowStock,
  ),
  _HubTile(
    Key('inventory-tile-out-of-stock'),
    Icons.remove_shopping_cart_outlined,
    'Out of stock',
    'Products customers cannot order right now',
    Routes.outOfStock,
  ),
  _HubTile(
    Key('inventory-tile-discontinued'),
    Icons.block_outlined,
    'Discontinued',
    'Listings you have stopped selling',
    Routes.discontinuedStock,
  ),
  _HubTile(
    Key('inventory-tile-freshness'),
    Icons.update_outlined,
    'Inventory freshness',
    'Listings that have not been touched lately',
    Routes.inventoryFreshness,
  ),
  _HubTile(
    Key('inventory-tile-sync-status'),
    Icons.sync_outlined,
    'Inventory sync status',
    'Where each stock update came from',
    Routes.inventorySyncStatus,
  ),
];

const List<_HubTile> _actionTiles = [
  _HubTile(
    Key('inventory-tile-update-stock'),
    Icons.edit_note_outlined,
    'Update stock',
    'Record a delivery, damage or correction',
    Routes.updateStock,
  ),
  _HubTile(
    Key('inventory-tile-stock-history'),
    Icons.history_outlined,
    'Stock history',
    'Movements, adjustments and price changes',
    Routes.stockHistory,
  ),
];

const List<_HubTile> _relatedTiles = [
  _HubTile(
    Key('inventory-tile-price-list'),
    Icons.currency_rupee_outlined,
    'Price list',
    'Review and update product pricing',
    Routes.priceList,
  ),
  _HubTile(
    Key('inventory-tile-import-center'),
    Icons.upload_file_outlined,
    'Import Center',
    'Bulk-update inventory from Excel',
    Routes.importCenter,
  ),
];

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.items, this.summary});

  final List<ShopProductItem> items;
  final InventorySummary? summary;

  int get _staleCount => items.where((i) => i.isStale).length;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    final s = summary;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Health header ───────────────────────────────────────────────────
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Stock health',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: StatCard(
                          key: const Key('stat-total-products'),
                          label: 'Products',
                          value: s?.total ?? items.length,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: StatCard(
                          key: const Key('stat-total-units'),
                          label: 'Units in stock',
                          value:
                              s?.totalUnits ??
                              items.fold(0, (sum, i) => sum + i.quantity),
                          color: AppTheme.verifiedGreen,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: StatCard(
                          key: const Key('stat-low-stock'),
                          label: 'Low stock',
                          value:
                              s?.lowStock ??
                              items.where((i) => i.isLowStock).length,
                          color: AppTheme.pendingAmber,
                          onTap: () => context.push(Routes.lowStock),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: StatCard(
                          key: const Key('stat-out-of-stock'),
                          label: 'Out of stock',
                          value:
                              s?.outOfStock ??
                              items.where((i) => i.isOutOfStock).length,
                          color: AppTheme.rejectedRed,
                          onTap: () => context.push(Routes.outOfStock),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: StatCard(
                          key: const Key('stat-stale'),
                          label: 'Needs update',
                          value: _staleCount,
                          color: AppTheme.pendingAmber,
                          onTap: () => context.push(Routes.inventoryFreshness),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _section(context, 'Stock views', _stockTiles),
          const SizedBox(height: 16),
          _section(context, 'Actions', _actionTiles),
          const SizedBox(height: 16),
          _section(context, 'Pricing & imports', _relatedTiles),
          const SizedBox(height: 8),
          Text(
            'Counts come straight from your shop\'s live inventory.',
            style: TextStyle(fontSize: 11, color: outline),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<_HubTile> tiles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, color: Theme.of(context).dividerColor),
                ListTile(
                  key: tiles[i].key,
                  leading: Icon(
                    tiles[i].icon,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(tiles[i].title),
                  subtitle: Text(
                    tiles[i].subtitle,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(tiles[i].route),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
