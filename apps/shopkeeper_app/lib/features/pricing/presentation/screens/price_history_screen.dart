import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          : _PriceChangeList(error: _load?.error, changes: changes),
    );
  }
}

class _PriceChangeList extends StatelessWidget {
  const _PriceChangeList({required this.error, required this.changes});

  final String? error;
  final List<ProductHistoryEntry> changes;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: outline),
              const SizedBox(height: 12),
              Text(error!, textAlign: TextAlign.center),
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
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: changes.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
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
            backgroundColor: Color(0x1A1A73E8),
            child: Icon(Icons.currency_rupee_outlined,
                size: 16, color: Color(0xFF1A73E8)),
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
