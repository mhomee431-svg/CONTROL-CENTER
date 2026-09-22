import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/ui/load_more.dart';
import '../../../products/domain/product_models.dart';
import '../../../products/presentation/controllers/products_controller.dart';
import '../widgets/pricing_shared.dart';
import '../../../inventory/presentation/widgets/inventory_shared.dart'
    show moneyLabel, lastUpdatedLabel;

/// Price History — the price_change slice of one product's audit trail:
/// old → new selling price (and MRP), plus what triggered the change.
///
/// Opened with a product (from the price list) or with a product picker.
class PriceHistoryScreen extends ConsumerStatefulWidget {
  const PriceHistoryScreen({super.key, this.product});

  final ShopProductItem? product;

  @override
  ConsumerState<PriceHistoryScreen> createState() =>
      _PriceHistoryScreenState();
}

class _PriceHistoryScreenState extends ConsumerState<PriceHistoryScreen> {
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

  /// Fetches the NEXT page of the audit trail and keeps only its price changes.
  ///
  /// The endpoint pages the WHOLE trail (movements, adjustments and price
  /// changes), so a price list can need more than one page to surface the older
  /// changes — which is why the footer reports the entries still behind the
  /// page break rather than pretending the visible list is all there is.
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
        appBar: AppBar(title: const Text('Price history')),
        body: PricingAsyncBody(
          status: products.status,
          message: products.message,
          onRetry: () => ref.read(productsControllerProvider.notifier).load(),
          builder: (context) => PricingProductPicker(
            items: products.items,
            onSelected: (item) => setState(() {
              _selected = item;
              _loadHistory();
            }),
          ),
        ),
      );
    }

    final changes = (_load?.history?.entries ?? const <ProductHistoryEntry>[])
        .where((e) => e.type == 'price_change')
        .toList();

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
          : _PriceChangeList(
              error: _load?.error,
              changes: changes,
              history: _load?.history,
              onLoadMore: _loadMore,
              loadingMore: _loadingMore,
              onRetry: _loadHistory,
            ),
    );
  }
}

class _PriceChangeList extends StatelessWidget {
  const _PriceChangeList({
    required this.error,
    required this.changes,
    required this.history,
    required this.onLoadMore,
    required this.loadingMore,
    required this.onRetry,
  });

  final String? error;
  final List<ProductHistoryEntry> changes;

  /// The page the price changes were taken from — it carries the server's
  /// pagination state (`total` / `has_more`) the footer reads.
  final ProductHistoryResult? history;

  /// Reveals the next page of the audit trail.
  final Future<void> Function() onLoadMore;

  /// True while that next page is in flight.
  final bool loadingMore;

  /// Re-reads the first page (used by the error state).
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;

    // A failure with nothing loaded is the full error state; once changes are
    // on screen a failure is a footnote under them, so a page that did not
    // arrive can never hide the prices already fetched.
    if (error != null && changes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: outline),
              const SizedBox(height: 12),
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (changes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.currency_rupee_outlined, size: 40, color: outline),
            const SizedBox(height: 12),
            const Text('No price changes yet'),
            const SizedBox(height: 4),
            Text(
              'Every price update for this product will be recorded here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: outline),
            ),
            // The FIRST page can hold zero price changes while the trail
            // continues (movements sort alongside them): the empty state stays
            // truthful about what has been SEEN, and the next page stays
            // reachable instead of ending the list here.
            if (history?.hasMore ?? false)
              _PricePageFooter(
                error: error,
                hasMore: true,
                hidden: history?.hidden,
                loadingMore: loadingMore,
                onLoadMore: onLoadMore,
              ),
          ],
        ),
      );
    }

    final hasMore = history?.hasMore ?? false;
    // One extra row for the footer whenever there is something to report there
    // (a further page, a page in flight, or a page that failed).
    final showFooter = hasMore || loadingMore || error != null;

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: changes.length + (showFooter ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        if (i >= changes.length) {
          return _PricePageFooter(
            error: error,
            hasMore: hasMore,
            hidden: history?.hidden,
            loadingMore: loadingMore,
            onLoadMore: onLoadMore,
          );
        }
        final e = changes[i];
        final title = e.oldPrice != null && e.newPrice != null
            ? '${moneyLabel(e.oldPrice!)} → ${moneyLabel(e.newPrice!)}'
            : e.newPrice != null
                ? 'Set to ${moneyLabel(e.newPrice!)}'
                : 'Price updated';
        final mrp = e.oldMrp != null || e.newMrp != null
            ? 'MRP ${e.oldMrp == null ? '—' : moneyLabel(e.oldMrp!)} → '
                '${e.newMrp == null ? '—' : moneyLabel(e.newMrp!)}'
            : null;
        final source = e.changeSource == null ? null : 'via ${e.changeSource}';
        final detail = [mrp, source].whereType<String>().join(' · ');

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primarySoft,
            child: Icon(Icons.currency_rupee_outlined,
                size: 16, color: AppColors.primary),
          ),
          title: Text(title,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (detail.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(detail, style: TextStyle(fontSize: 12, color: outline)),
              ],
              const SizedBox(height: 2),
              Text(
                e.occurredAt == null ? '—' : lastUpdatedLabel(e.occurredAt),
                style: TextStyle(fontSize: 11, color: outline),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The page break of the price list.
///
/// The price history is a VIEW over the product's whole audit trail (movements,
/// adjustments and price changes), so the number it reports is the audit entries
/// still behind the server's page break — never a claim that the visible price
/// list is complete. A failed page says why and keeps the rows on screen.
class _PricePageFooter extends StatelessWidget {
  const _PricePageFooter({
    required this.error,
    required this.hasMore,
    required this.hidden,
    required this.loadingMore,
    required this.onLoadMore,
  });

  final String? error;
  final bool hasMore;
  final int? hidden;
  final bool loadingMore;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return Column(
      children: [
        if (hasMore)
          LoadMoreTile(
            key: const Key('price-history-load-more'),
            hidden: hidden,
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
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              error!,
              key: const Key('price-history-page-error'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: outline),
            ),
          ),
      ],
    );
  }
}

