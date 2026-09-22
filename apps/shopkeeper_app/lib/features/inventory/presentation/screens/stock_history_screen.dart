import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/load_more.dart';
import '../../../products/domain/product_models.dart';
import '../../../products/presentation/controllers/products_controller.dart';
import '../widgets/inventory_shared.dart';

/// Stock History — the full audit trail of one product: stock movements,
/// adjustments and price changes, exactly as the backend recorded them.
///
/// Opened with a product (from the inventory list) or with a product picker.
class StockHistoryScreen extends ConsumerStatefulWidget {
  const StockHistoryScreen({super.key, this.product});

  final ShopProductItem? product;

  @override
  ConsumerState<StockHistoryScreen> createState() =>
      _StockHistoryScreenState();
}

class _StockHistoryScreenState extends ConsumerState<StockHistoryScreen> {
  ShopProductItem? _selected;
  ProductHistoryLoad? _load;
  bool _loading = false;

  /// True while the next page of the trail is in flight.
  bool _loadingMore = false;

  bool get _pickerMode => widget.product == null && _selected == null;

  @override
  void initState() {
    super.initState();
    _selected = widget.product;
    Future.microtask(() {
      final state = ref.read(productsControllerProvider);
      if (_pickerMode &&
          state.status == ProductsStatus.loading &&
          state.items.isEmpty) {
        ref.read(productsControllerProvider.notifier).load();
      } else if (!_pickerMode) {
        _loadHistory();
      }
    });
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    final load = await ref
        .read(productsControllerProvider.notifier)
        .loadHistory(_product.id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _load = load;
    });
  }

  /// Fetches the NEXT page of the audit trail.
  ///
  /// The server pages it (`limit`/`offset` + `has_more`): the request starts at
  /// the offset the loaded page ended at, and the returned page is stitched on
  /// by the controller's shared append rule. A failed page keeps every entry
  /// already on screen.
  Future<void> _loadMore() async {
    final history = _load?.history;
    if (history == null || !history.hasMore || _loadingMore) return;
    setState(() => _loadingMore = true);
    final load = await ref
        .read(productsControllerProvider.notifier)
        .loadMoreHistory(_product.id, history);
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      _load = load;
    });
  }

  ShopProductItem get _product => _selected ?? widget.product!;

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsControllerProvider);

    if (_pickerMode) {
      return Scaffold(
        appBar: AppBar(title: const Text('Stock history')),
        body: ProductsAsyncBody(
          status: products.status,
          message: products.message,
          onRetry: () => ref.read(productsControllerProvider.notifier).load(),
          builder: (context) => ProductPickerListView(
            items: products.items,
            onSelected: (item) => setState(() {
              _selected = item;
              _loadHistory();
            }),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_product.name, style: const TextStyle(fontSize: 17)),
        actions: [
          if (widget.product == null)
            IconButton(
              tooltip: 'Choose another product',
              icon: const Icon(Icons.swap_horiz_outlined),
              onPressed: () => setState(() {
                _selected = null;
                _load = null;
              }),
            ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_outlined),
            onPressed: _loading ? null : _loadHistory,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _HistoryList(
              load: _load,
              onRefresh: _loadHistory,
              onLoadMore: _loadMore,
              loadingMore: _loadingMore,
            ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.load,
    required this.onRefresh,
    required this.onLoadMore,
    required this.loadingMore,
  });

  final ProductHistoryLoad? load;

  /// Re-fetches the trail (pull-to-refresh / retry). Owned by the screen so
  /// the summary tile and the entries always come from the same fetch.
  final Future<void> Function() onRefresh;

  /// Reveals the next page of the trail (the server pages it).
  final Future<void> Function() onLoadMore;

  /// True while that next page is in flight.
  final bool loadingMore;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    final history = load?.history;
    final entries = history?.entries ?? const <ProductHistoryEntry>[];

    // Always scrollable so pull-to-refresh works even when the trail is empty
    // or failed — the shopkeeper is never stuck without a way to retry.
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (history != null) StockHistorySummary(history: history),
          // A failure with nothing loaded is the full error state; a failure
          // after entries are on screen is a footnote under them, so a page
          // that did not arrive can never hide the trail already fetched.
          if (load?.error != null && entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(Icons.error_outline, size: 40, color: outline),
                  const SizedBox(height: 12),
                  Text(load!.error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            )
          else if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(Icons.history_outlined, size: 40, color: outline),
                  const SizedBox(height: 12),
                  const Text('No history yet'),
                  const SizedBox(height: 4),
                  Text(
                    'Stock movements, adjustments and price changes will '
                    'appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: outline),
                  ),
                ],
              ),
            )
          else ...[
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _EntryTile(entry: entries[i]),
            ],
            // Older entries stay behind the server's page break until asked
            // for — the trail is a paged endpoint, not one giant response.
            if (history != null && history.hasMore)
              LoadMoreTile(
                key: const Key('stock-history-load-more'),
                hidden: history.hidden,
                onTap: loadingMore ? () {} : onLoadMore,
              ),
            if (loadingMore)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            if (load?.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  load!.error!,
                  key: const Key('stock-history-page-error'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: outline),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final ProductHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    final (icon, color, title, detail) = _describe();

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(icon, size: 16, color: color),
      ),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (detail != null) ...[
            const SizedBox(height: 2),
            Text(detail, style: TextStyle(fontSize: 12, color: outline)),
          ],
          const SizedBox(height: 2),
          Text(
            entry.occurredAt == null ? '—' : lastUpdatedLabel(entry.occurredAt),
            style: TextStyle(fontSize: 11, color: outline),
          ),
          const SizedBox(height: 2),
          Text(
            entry.actorLabel,
            style: TextStyle(fontSize: 11, color: outline),
          ),
        ],
      ),
    );
  }

  (IconData, Color, String, String?) _describe() {
    switch (entry.type) {
      case 'price_change':
        final oldP = entry.oldPrice;
        final newP = entry.newPrice;
        final title = oldP != null && newP != null
            ? 'Price ${moneyLabel(oldP)} → ${moneyLabel(newP)}'
            : 'Price updated';
        final mrp = entry.oldMrp != null || entry.newMrp != null
            ? 'MRP ${entry.oldMrp == null ? '—' : moneyLabel(entry.oldMrp!)} → '
                '${entry.newMrp == null ? '—' : moneyLabel(entry.newMrp!)}'
            : null;
        final source =
            entry.changeSource == null ? null : 'via ${entry.changeSource}';
        final detail = [mrp, source].whereType<String>().join(' · ');
        return (
          Icons.currency_rupee_outlined,
          AppColors.primary,
          title,
          detail.isEmpty ? null : detail,
        );
      case 'adjustment':
        final delta = entry.quantityAdjustment ?? 0;
        final title =
            '${delta > 0 ? '+' : ''}$delta units · ${entry.adjustmentType ?? 'CORRECTION'}';
        return (
          delta >= 0 ? Icons.add_circle_outline : Icons.remove_circle_outline,
          delta >= 0 ? AppTheme.verifiedGreen : AppTheme.rejectedRed,
          title,
          entry.reason,
        );
      default: // movement
        final delta = entry.quantityChange ?? 0;
        final before = entry.quantityBefore;
        final after = entry.quantityAfter;
        final title =
            '${delta > 0 ? '+' : ''}$delta units · ${entry.movementType ?? 'MOVEMENT'}';
        final detail = before != null && after != null
            ? '$before → $after units${entry.source == null ? '' : ' · ${entry.source}'}'
            : entry.source;
        return (
          delta >= 0
              ? Icons.arrow_downward_outlined
              : Icons.arrow_upward_outlined,
          delta >= 0 ? AppTheme.verifiedGreen : AppTheme.pendingAmber,
          title,
          detail,
        );
    }
  }
}
