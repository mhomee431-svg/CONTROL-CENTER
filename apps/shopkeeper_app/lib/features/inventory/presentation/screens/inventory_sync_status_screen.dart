import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../products/domain/product_models.dart';
import '../../../products/presentation/controllers/products_controller.dart';
import '../widgets/inventory_shared.dart';

/// Inventory Sync Status — WHERE each product's stock figure came from and
/// WHEN it was last touched (app edit, barcode scan, POS sync, Excel import).
///
/// Shows a per-source breakdown plus the overall last-sync time, with links
/// to the POS integration screen and the Excel import history.
class InventorySyncStatusScreen extends ConsumerStatefulWidget {
  const InventorySyncStatusScreen({super.key});

  @override
  ConsumerState<InventorySyncStatusScreen> createState() =>
      _InventorySyncStatusScreenState();
}

class _InventorySyncStatusScreenState
    extends ConsumerState<InventorySyncStatusScreen> {
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
      appBar: AppBar(title: Text(appText(context).commonInventorySyncStatus)),
      body: ProductsAsyncBody(
        status: state.status,
        message: state.message,
        onRetry: () => ref.read(productsControllerProvider.notifier).load(),
        // Pull is the silent path: the sync cards stay on screen while fresh
        // source data loads.
        onRefresh: () =>
            ref.read(productsControllerProvider.notifier).refresh(),
        builder: (context) => _SyncStatusBody(items: state.items),
      ),
    );
  }
}

class _SyncStatusBody extends StatelessWidget {
  const _SyncStatusBody({required this.items});

  final List<ShopProductItem> items;

  /// Products grouped by their server-reported inventory source.
  Map<String, List<ShopProductItem>> get _bySource {
    final map = <String, List<ShopProductItem>>{};
    for (final item in items) {
      final key = inventorySourceLabel(item.source);
      map.putIfAbsent(key, () => []).add(item);
    }
    return map;
  }

  DateTime? get _lastSync {
    DateTime? latest;
    for (final item in items) {
      final when = item.lastUpdated;
      if (when != null && (latest == null || when.isAfter(latest))) {
        latest = when;
      }
    }
    return latest;
  }

  DateTime? _newest(List<ShopProductItem> group) {
    DateTime? latest;
    for (final item in group) {
      final when = item.lastUpdated;
      if (when != null && (latest == null || when.isAfter(latest))) {
        latest = when;
      }
    }
    return latest;
  }

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    final groups = _bySource.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    // Always scrollable: pull-to-refresh must fire even when the summary
    // cards fit on one screen.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        // ── Overall sync card ───────────────────────────────────────────────
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.sync_outlined, color: AppTheme.verifiedGreen),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(appText(context).commonLastInventoryUpdate,
                          style: TextStyle(fontSize: 13)),
                      Text(
                        lastUpdatedLabel(_lastSync),
                        key: const Key('sync-last-update'),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _SourceBreakdown(groups: groups, newest: _newest),
        const SizedBox(height: 16),
        _ProductRows(items: items),
        const SizedBox(height: 16),
        _RelatedLinks(),
        const SizedBox(height: 8),
        Text(
          appText(context).inventorySyncStatusScreenSourceLabelsComeFromThe,
          style: TextStyle(fontSize: 11, color: outline),
        ),
      ],
    );
  }
}

class _SourceBreakdown extends StatelessWidget {
  const _SourceBreakdown({required this.groups, required this.newest});

  final List<MapEntry<String, List<ShopProductItem>>> groups;
  final DateTime? Function(List<ShopProductItem>) newest;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(appText(context).commonBySource, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < groups.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, color: Theme.of(context).dividerColor),
                ListTile(
                  leading: Icon(
                    inventorySourceIcon(groups[i].value.first.source),
                    color: inventorySourceColor(groups[i].value.first.source),
                  ),
                  title: Text(groups[i].key),
                  subtitle: Text(
                    lastUpdatedLabel(newest(groups[i].value)),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Text(
                    appText(context).inventorySyncStatusScreenLength(groups[i].value.length),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ProductRows extends StatelessWidget {
  const _ProductRows({required this.items});

  final List<ShopProductItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(appText(context).commonProducts2, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (final item in items)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      InfoChip(
                        label: lastUpdatedLabel(item.lastUpdated),
                        color: freshnessColor(item.freshnessStatus),
                      ),
                      const SizedBox(width: 6),
                      InfoChip(
                        label: inventorySourceLabel(item.source),
                        color: inventorySourceColor(item.source),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RelatedLinks extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('sync-open-pos'),
            onPressed: () => context.push(Routes.pos),
            icon: const Icon(Icons.point_of_sale_outlined, size: 18),
            label: Text(appText(context).commonPOSSync2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('sync-open-import-history'),
            onPressed: () => context.push(Routes.importHistory),
            icon: const Icon(Icons.upload_file_outlined, size: 18),
            label: Text(appText(context).commonExcelImports2),
          ),
        ),
      ],
    );
  }
}
