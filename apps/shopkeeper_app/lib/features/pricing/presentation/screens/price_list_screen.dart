import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/state/system_state_view.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/cached_data_notice.dart';
import '../../../../core/ui/debounced_search_field.dart';
import '../../../../core/ui/lazy_list.dart';
import '../../../../core/ui/load_more.dart';
import '../../../../core/utils/datetime_utils.dart';
import '../../../products/domain/product_models.dart';
import '../../../products/presentation/controllers/products_controller.dart';
import '../../../products/presentation/controllers/recent_searches_controller.dart';
import '../controllers/price_list_controller.dart';
import '../widgets/pricing_shared.dart';
import '../../../inventory/presentation/widgets/inventory_shared.dart'
    show moneyLabel, trimNumber;

/// Price List — every product with its current price, MRP and implied
/// discount. Tap a row to open Update Price; the app bar exposes the shop-wide
/// pricing surfaces (Price History, Create Offer).
///
/// The shopkeeper's own state (the search text and the page) lives in the
/// price list's view controller, which is why leaving this screen and coming
/// back keeps both.
class PriceListScreen extends ConsumerStatefulWidget {
  const PriceListScreen({super.key});

  @override
  ConsumerState<PriceListScreen> createState() => _PriceListScreenState();
}

class _PriceListScreenState extends ConsumerState<PriceListScreen> {
  /// The query itself lives in the view controller;
  /// [DebouncedSearchField] mirrors it internally, seeded from the query on
  /// mount, which is what brings the shopkeeper's search text back with the
  /// screen.

  PriceListController get _controller =>
      ref.read(priceListControllerProvider.notifier);

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
    final catalog = ref.watch(productsControllerProvider);
    // The view state is watched (a keystroke rebuilds the list); the page is
    // derived from the catalog rows + the search text, and memoized inside
    // the controller: a rebuild that changed neither runs neither.
    ref.watch(priceListControllerProvider);
    final page =
        ref.watch(priceListControllerProvider.notifier).pageFor(catalog.items);
    // Shared product-search history: submitted terms only, most-recent-first.
    final recents = ref.watch(recentSearchesControllerProvider).terms;

    return Scaffold(
      appBar: AppBar(
        title: Text(appText(context).commonPriceList),
        actions: [
          IconButton(
            key: const Key('price-list-history'),
            tooltip: appText(context).commonPriceHistory2,
            icon: const Icon(Icons.history_outlined),
            onPressed: () => context.push(Routes.priceHistory),
          ),
          IconButton(
            key: const Key('price-list-create-offer'),
            tooltip: appText(context).commonCreateOffer5,
            icon: const Icon(Icons.local_offer_outlined),
            onPressed: () => context.push(Routes.createOffer),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: DebouncedSearchField(
              key: const Key('price-search-field'),
              hintText: appText(context).priceListScreenSearchNameBrandOrSKU,
              initialValue: ref
                  .read(priceListControllerProvider)
                  .query
                  .search,
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
          Expanded(
            child: PricingAsyncBody(
              status: catalog.status,
              message: catalog.message,
              onRetry: () =>
                  ref.read(productsControllerProvider.notifier).load(),
              // Pull is the silent path: the price rows stay on screen while
              // fresh ones load (Retry keeps the loud spinner).
              onRefresh: () =>
                  ref.read(productsControllerProvider.notifier).refresh(),
              builder: (context) => LazyListView(
                // Rows are built lazily, like the products and inventory
                // lists — a keystroke re-filters the catalog, only the rows
                // near the viewport rebuild.
                // Always scrollable: pull-to-refresh must fire even when the
                // price book fits on one screen.
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: page.rows.length,
                // Provenance first: a stale cached PRICE that looks live is
                // the most dangerous case of all, so it is labelled loudly.
                header: [
                  if (catalog.fromCache)
                    const CachedDataNotice(
                      message: 'Showing your last synced prices — these may '
                          'have changed. Reconnect to refresh.',
                    ),
                ],
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 16),
                itemBuilder: (context, i) => _PriceRow(
                  item: page.rows[i],
                  onTap: () =>
                      context.push(Routes.updatePrice, extra: page.rows[i]),
                ),
                // The page break: only a price book bigger than one page ever
                // shows it, and it names how many rows are still behind it.
                footer: [
                  if (page.hasMore)
                    LoadMoreTile(
                      key: const Key('price-list-load-more'),
                      hidden: page.hidden,
                      onTap: _controller.showMore,
                    ),
                ],
                // A filter that matched nothing is a different story from an
                // empty catalog — each branch keeps its own copy, the layout
                // is the shared empty state (centred by the lazy list).
                emptyPlaceholder: SystemStateView.empty(
                  title: page.isEmptyCatalog
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
    // A stale PRICE that looks live is the dangerous case, so the age line
    // turns amber once the last update is over a day old (same threshold and
    // vocabulary as Inventory and POS).
    final stale = DateTimeUtils.isStale(item.lastUpdated);

    return ListTile(
      onTap: onTap,
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.mrp != null && item.mrp! > item.price
                ? 'MRP ${moneyLabel(item.mrp!)}'
                      '${discount == null ? '' : ' · ${trimNumber(discount)}% off'}'
                : item.mrp == null
                ? 'No MRP set'
                : 'MRP ${moneyLabel(item.mrp!)}',
            style: TextStyle(fontSize: 12, color: outline),
          ),
          if (item.lastUpdated != null) ...[
            const SizedBox(height: 2),
            Text(
              DateTimeUtils.formatPriceFreshness(item.lastUpdated),
              style: TextStyle(
                fontSize: 11,
                color: stale ? AppTheme.pendingAmber : outline,
                fontWeight: stale ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ],
      ),
      trailing: Text(
        moneyLabel(item.price),
        key: Key('price-value-${item.id}'),
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    );
  }
}

