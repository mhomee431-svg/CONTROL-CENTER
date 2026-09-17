import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/state/system_state_view.dart';
import '../../../../core/ui/lazy_list.dart';
import '../../../products/domain/product_models.dart';
import '../../../products/domain/product_search.dart';
import '../../../products/presentation/controllers/products_controller.dart';
import '../widgets/pricing_shared.dart';
import '../../../inventory/presentation/widgets/inventory_shared.dart'
    show moneyLabel, trimNumber;

/// Price List — every product with its current price, MRP and implied
/// discount. Tap a row to open Update Price; the app bar exposes the shop-wide
/// pricing surfaces (Price History, Create Offer).
class PriceListScreen extends ConsumerStatefulWidget {
  const PriceListScreen({super.key});

  @override
  ConsumerState<PriceListScreen> createState() => _PriceListScreenState();
}

class _PriceListScreenState extends ConsumerState<PriceListScreen> {
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(productsControllerProvider);
    // Same predicate as the products list and the inventory scopes (see
    // [ProductSearch]) so "search" can never mean two things in one app.
    final search = _searchIndex.of(state.items);
    final query = _query.trim();
    final visible =
        state.items.where((i) => search.matches(i, query)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Price list'),
        actions: [
          IconButton(
            key: const Key('price-list-history'),
            tooltip: 'Price history',
            icon: const Icon(Icons.history_outlined),
            onPressed: () => context.push(Routes.priceHistory),
          ),
          IconButton(
            key: const Key('price-list-create-offer'),
            tooltip: 'Create offer',
            icon: const Icon(Icons.local_offer_outlined),
            onPressed: () => context.push(Routes.createOffer),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              key: const Key('price-search-field'),
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Search name, brand or SKU',
                prefixIcon: Icon(Icons.search_outlined),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: PricingAsyncBody(
              status: state.status,
              message: state.message,
              onRetry: () =>
                  ref.read(productsControllerProvider.notifier).load(),
              builder: (context) => LazyListView(
                // Rows are built lazily, like the products and inventory
                // lists — a keystroke re-filters the catalog, only the rows
                // near the viewport rebuild.
                itemCount: visible.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 16),
                itemBuilder: (context, i) => _PriceRow(
                  item: visible[i],
                  onTap: () =>
                      context.push(Routes.updatePrice, extra: visible[i]),
                ),
                // A filter that matched nothing is a different story from an
                // empty catalog — each branch keeps its own copy, the layout
                // is the shared empty state (centred by the lazy list).
                emptyPlaceholder: SystemStateView.empty(
                  title: query.isEmpty
                      ? 'No products yet. Add products or import them from '
                            'Excel first.'
                      : 'No products match your search',
                  icon: Icons.currency_rupee_outlined,
                  iconColor: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.item, this.onTap});

  final ShopProductItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    final discount = discountPercentOff(item.mrp, item.price);

    return ListTile(
      onTap: onTap,
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        item.mrp != null && item.mrp! > item.price
            ? 'MRP ${moneyLabel(item.mrp!)}'
                  '${discount == null ? '' : ' · ${trimNumber(discount)}% off'}'
            : item.mrp == null
            ? 'No MRP set'
            : 'MRP ${moneyLabel(item.mrp!)}',
        style: TextStyle(fontSize: 12, color: outline),
      ),
      trailing: Text(
        moneyLabel(item.price),
        key: Key('price-value-${item.id}'),
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    );
  }
}
