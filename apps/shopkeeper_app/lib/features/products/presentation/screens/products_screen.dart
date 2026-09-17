import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/state/system_state.dart';
import '../../../../core/state/system_state_view.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/lazy_list.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../../offers/presentation/controllers/offers_controller.dart';
import '../../../offers/presentation/widgets/offer_create_sheet.dart';
import '../../domain/product_models.dart';
import '../../domain/product_search.dart';
import '../controllers/products_controller.dart';
import '../widgets/product_details_sheet.dart';
import '../widgets/product_sheets.dart';
import '../widgets/stock_sheets.dart';

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(productsControllerProvider.notifier).load(),
    );
  }

  void _resetOfferSheet() =>
      ref.read(offersControllerProvider.notifier).reset();

  @override
  Widget build(BuildContext context) {
    ref.listen(selectedShopProvider, (prev, next) {
      if (prev?.id != next?.id) {
        ref.read(productsControllerProvider.notifier).load();
      }
    });

    final state = ref.watch(productsControllerProvider);
    final ready = state.status == ProductsStatus.ready;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Products & inventory'),
        actions: [
          IconButton(
            icon: const Icon(Icons.local_offer_outlined),
            tooltip: 'Create offer',
            onPressed: ready
                ? () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const OfferCreateSheet(),
                    ).then((_) => _resetOfferSheet())
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.upload_file_outlined),
            tooltip: 'Import from Excel',
            onPressed: ready ? () => context.push(Routes.inventoryImport) : null,
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan barcode',
            onPressed: ready ? () => context.push(Routes.scanBarcode) : null,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-product',
        // Req 24: the FAB opens the method chooser (manual / barcode /
        // bulk Excel) — power users still have the AppBar shortcuts.
        onPressed: ready
            ? () => showModalBottomSheet(
                context: context,
                builder: (_) => const ProductAddMethodSheet(),
              )
            : null,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: SafeArea(
        // Loading / permission-denied / error all go through the shared
        // system-state body, so the async contract exists in ONE place.
        //
        // `isEmpty` stays false on purpose: an empty catalog is NOT a system
        // state here — the counters, search box and filters must stay on screen
        // (the shopkeeper's next move is "Add"), and `_ReadyBody` owns that copy.
        child: SystemStateBody(
          isLoading: state.status == ProductsStatus.loading,
          failure: switch (state.status) {
            ProductsStatus.accessDenied => SystemStateSpec.resolve(
              state: SystemState.permissionDenied,
              title: 'No access to this shop',
              message: state.message,
              fallbackMessage: 'You do not have access to this shop.',
            ),
            ProductsStatus.error => SystemStateSpec.resolve(
              title: 'Could not load inventory',
              message: state.message,
              fallbackMessage: 'Please check your connection and retry.',
            ),
            _ => null,
          },
          onRetry: () => ref.read(productsControllerProvider.notifier).load(),
          onSwitchShop: () => context.go(Routes.shops),
          builder: (_) => RefreshIndicator(
            onRefresh: () =>
                ref.read(productsControllerProvider.notifier).load(),
            child: _ReadyBody(allItems: state.items, summary: state.summary),
          ),
        ),
      ),
    );
  }
}

enum ProductSort { name, price, stock, recentlyUpdated }

class ProductFilterApplied {
  const ProductFilterApplied({
    this.search = '',
    this.stock = 'all',
    this.availability,
    this.category,
    this.brand,
    this.minPrice,
    this.maxPrice,
    this.recentlyUpdated = false,
  });

  final String search;
  final String stock;
  final bool? availability;
  final String? category;
  final String? brand;
  final double? minPrice;
  final double? maxPrice;
  final bool recentlyUpdated;

  bool get hasActiveFilters =>
      stock != 'all' ||
      availability != null ||
      category != null ||
      brand != null ||
      minPrice != null ||
      maxPrice != null ||
      recentlyUpdated;

  ProductFilterApplied copyWith({
    String? search,
    String? stock,
    bool? availability,
    String? category,
    String? brand,
    double? minPrice,
    double? maxPrice,
    bool? recentlyUpdated,
  }) {
    return ProductFilterApplied(
      search: search ?? this.search,
      stock: stock ?? this.stock,
      availability: availability ?? this.availability,
      category: category ?? this.category,
      brand: brand ?? this.brand,
      minPrice: minPrice ?? this.minPrice,
      maxPrice: maxPrice ?? this.maxPrice,
      recentlyUpdated: recentlyUpdated ?? this.recentlyUpdated,
    );
  }
}


class _ReadyBody extends ConsumerStatefulWidget {
  const _ReadyBody({required this.allItems, required this.summary});

  final List<ShopProductItem> allItems;
  final InventorySummary? summary;

  @override
  ConsumerState<_ReadyBody> createState() => _ReadyBodyState();
}

class _ReadyBodyState extends ConsumerState<_ReadyBody> {
  final TextEditingController _search = TextEditingController();
  ProductSort _sort = ProductSort.recentlyUpdated;
  ProductFilterApplied _filter = const ProductFilterApplied();

  /// Searchable text, indexed once per catalog instead of once per keystroke.
  final ProductSearchCache _searchIndex = ProductSearchCache();

  /// Last filtered + sorted result, with the inputs it was built from.
  List<ShopProductItem>? _visibleCache;
  ProductFilterApplied? _visibleForFilter;
  ProductSort? _visibleForSort;
  List<ShopProductItem>? _visibleForItems;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _message() {
    final state = ref.read(productsControllerProvider);
    if (state.message == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(state.message!)));
      ref.read(productsControllerProvider.notifier).clearTransientMessage();
    });
  }

  /// Filtered + sorted rows, recomputed only when one of its inputs actually
  /// changed: the search text, a filter, the sort, or the catalog itself.
  ///
  /// One shared, pre-indexed predicate covers every human-readable identity of
  /// a listing (name, brand, SKU, variant) — the same predicate the inventory
  /// scopes and the price list use, so "search" can never mean two things. The
  /// guard below it means a rebuild that has nothing to do with the list (a
  /// snackbar, an availability flip) reuses the previous answer instead of
  /// re-running the predicate over every product.
  List<ShopProductItem> get _visible {
    if (_visibleCache != null &&
        _visibleForSort == _sort &&
        _visibleForFilter == _filter &&
        identical(_visibleForItems, widget.allItems)) {
      return _visibleCache!;
    }

    final search = _searchIndex.of(widget.allItems);

    final items = widget.allItems.where((i) {
      if (!search.matches(i, _filter.search)) return false;

      switch (_filter.stock) {
        case 'in_stock':
          if (i.stockStatus != 'IN_STOCK') return false;
          break;
        case 'low_stock':
          if (i.stockStatus != 'LOW_STOCK' &&
              i.stockStatus != 'LIMITED_STOCK') {
            return false;
          }
          break;
        case 'out_of_stock':
          if (i.stockStatus != 'OUT_OF_STOCK') return false;
          break;
        default:
          break;
      }

      if (_filter.availability != null &&
          i.isAvailable != _filter.availability) {
        return false;
      }
      if (_filter.category != null && i.category != _filter.category) {
        return false;
      }
      if (_filter.brand != null && i.brand != _filter.brand) {
        return false;
      }
      if (_filter.minPrice != null && i.price < _filter.minPrice!) {
        return false;
      }
      if (_filter.maxPrice != null && i.price > _filter.maxPrice!) {
        return false;
      }
      if (_filter.recentlyUpdated && i.lastUpdated == null) return false;
      return true;
    }).toList(growable: false);

    switch (_sort) {
      case ProductSort.name:
        items.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case ProductSort.price:
        items.sort((a, b) => a.price.compareTo(b.price));
      case ProductSort.stock:
        items.sort((a, b) => b.quantity.compareTo(a.quantity));
      case ProductSort.recentlyUpdated:
        items.sort((a, b) {
          final ta = a.lastUpdated ?? DateTime.fromMillisecondsSinceEpoch(0);
          final tb = b.lastUpdated ?? DateTime.fromMillisecondsSinceEpoch(0);
          return tb.compareTo(ta);
        });
    }

    _visibleCache = items;
    _visibleForFilter = _filter;
    _visibleForSort = _sort;
    _visibleForItems = widget.allItems;
    return items;
  }

  /// Distinct, case-insensitively sorted values present in the loaded catalog
  /// — the option lists behind the filter sheet's Category / Brand pickers.
  /// Sourced from real rows so a filter can never be offered that matches
  /// nothing.
  List<String> _distinctValues(String? Function(ShopProductItem) pick) {
    final values = <String>{};
    for (final item in widget.allItems) {
      final value = pick(item)?.trim();
      if (value != null && value.isNotEmpty) values.add(value);
    }
    return values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  void _openFilters() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ProductFilterSheet(
        initial: _filter,
        categories: _distinctValues((i) => i.category),
        brands: _distinctValues((i) => i.brand),
        // Rebuild the filter instead of copyWith-ing it: copyWith treats a
        // `null` argument as "keep the previous value", which makes clearing
        // the Availability segment (or tapping Reset) a no-op.
        // Search + stock are edited outside the sheet, so keep them.
        onApply: (f) => setState(() {
          _filter = ProductFilterApplied(
            search: _filter.search,
            stock: _filter.stock,
            availability: f.availability,
            category: f.category,
            brand: f.brand,
            minPrice: f.minPrice,
            maxPrice: f.maxPrice,
            recentlyUpdated: f.recentlyUpdated,
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _message();
    final items = _visible;

    return LazyListView(
      padding: const EdgeInsets.all(16),
      style: LazyListStyle.card,
      itemCount: items.length,
      // Eager header: the summary, the search box and the filter/sort row are a
      // fixed handful of widgets, so they live outside the lazy row builder and
      // stay usable while the list below them is empty.
      header: [
        if (widget.summary != null) _SummaryChips(summary: widget.summary!),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          onChanged: (v) =>
              setState(() => _filter = _filter.copyWith(search: v)),
          decoration: InputDecoration(
            hintText: 'Search name, brand or SKU…',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            suffixIcon: _filter.search.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _search.clear();
                      setState(() => _filter = _filter.copyWith(search: ''));
                    },
                  ),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _FilterChip(
                label: 'All',
                selected: _filter.stock == 'all',
                onTap: () =>
                    setState(() => _filter = _filter.copyWith(stock: 'all')),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'In Stock',
                selected: _filter.stock == 'in_stock',
                onTap: () => setState(
                    () => _filter = _filter.copyWith(stock: 'in_stock')),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Low Stock',
                selected: _filter.stock == 'low_stock',
                onTap: () => setState(
                    () => _filter = _filter.copyWith(stock: 'low_stock')),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Out of Stock',
                selected: _filter.stock == 'out_of_stock',
                onTap: () => setState(
                    () => _filter = _filter.copyWith(stock: 'out_of_stock')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              // Hidden for an empty shop: "0 of 0 products" stacked on top of
              // "No products yet" is pure noise.
              child: widget.allItems.isEmpty
                  ? const SizedBox.shrink()
                  : Text(
                      '${items.length} of ${widget.allItems.length} products',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
            ),
            if (_filter.hasActiveFilters)
              TextButton.icon(
                onPressed: () {
                  _search.clear();
                  setState(() => _filter = const ProductFilterApplied());
                },
                icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                label: const Text('Clear'),
              ),
            IconButton(
              tooltip: 'Filters',
              onPressed: _openFilters,
              icon: Icon(
                Icons.filter_alt_outlined,
                color: _filter.hasActiveFilters
                    ? AppTheme.brandSeed
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            PopupMenuButton<ProductSort>(
              initialValue: _sort,
              onSelected: (v) => setState(() => _sort = v),
              tooltip: 'Sort',
              icon: const Icon(Icons.sort),
              itemBuilder: (_) => const [
                PopupMenuItem(value: ProductSort.name, child: Text('Name')),
                PopupMenuItem(value: ProductSort.price, child: Text('Price')),
                PopupMenuItem(value: ProductSort.stock, child: Text('Stock')),
                PopupMenuItem(
                    value: ProductSort.recentlyUpdated,
                    child: Text('Recently updated')),
              ],
            ),
          ],
        ),
        ],
      // Rows are built lazily: a keystroke re-filters the catalog, but only the
      // rows near the viewport are re-created, so a large shop stays
      // responsive instead of rebuilding every row per character.
      itemBuilder: (context, i) => _ProductTile(
        item: items[i],
        showDivider: i < items.length - 1,
        // Tapping a row opens read-only Product Details; every write
        // (edit/stock/history) is launched from there.
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => ProductDetailsSheet(item: items[i]),
        ),
        onToggle: (available) => ref
            .read(productsControllerProvider.notifier)
            .setAvailability(items[i].id, available),
        onUpdateStock: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => StockUpdateSheet(item: items[i]),
        ),
        onHistory: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => ProductHistorySheet(item: items[i]),
        ),
      ),
      // No rows: the feature's own explanation stands in for the list, inside
      // the same scroll view (so it stays reachable).
      emptyPlaceholder: _EmptyResults(
        catalogIsEmpty: widget.allItems.isEmpty,
        search: _filter.search,
        onClear: () {
          _search.clear();
          setState(() => _filter = const ProductFilterApplied());
        },
      ),
      footer: const [SizedBox(height: 32)],
    );
  }
}

class ProductFilterSheet extends StatefulWidget {
  const ProductFilterSheet({
    super.key,
    required this.initial,
    required this.onApply,
    this.categories = const [],
    this.brands = const [],
  });

  final ProductFilterApplied initial;
  final ValueChanged<ProductFilterApplied> onApply;

  /// Category / brand values present in the loaded catalog. An empty list
  /// hides that picker entirely — the sheet never offers a filter that
  /// cannot match a row.
  final List<String> categories;
  final List<String> brands;

  @override
  State<ProductFilterSheet> createState() => _ProductFilterSheetState();
}

class _ProductFilterSheetState extends State<ProductFilterSheet> {
  final _minController = TextEditingController();
  final _maxController = TextEditingController();
  bool? _availability;
  String? _category;
  String? _brand;
  bool _recentlyUpdated = false;

  @override
  void initState() {
    super.initState();
    _availability = widget.initial.availability;
    _category = widget.initial.category;
    _brand = widget.initial.brand;
    _recentlyUpdated = widget.initial.recentlyUpdated;
    final minP = widget.initial.minPrice;
    final maxP = widget.initial.maxPrice;
    _minController.text = minP == null ? '' : minP.toStringAsFixed(0);
    _maxController.text = maxP == null ? '' : maxP.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text('Filter products', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          _FilterSection(
            label: 'Availability',
            child: SegmentedButton<bool>(
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, label: Text('Available')),
                ButtonSegment(value: false, label: Text('Unavailable')),
              ],
              selected: _availability == null
                  ? const <bool>{}
                  : <bool>{_availability!},
              onSelectionChanged: (s) =>
                  setState(() => _availability = s.isEmpty ? null : s.first),
            ),
          ),
          if (widget.categories.isNotEmpty)
            _FilterSection(
              label: 'Category',
              child: _picker(
                options: widget.categories,
                value: _category,
                onChanged: (value) => setState(() => _category = value),
              ),
            ),
          if (widget.brands.isNotEmpty)
            _FilterSection(
              label: 'Brand',
              child: _picker(
                options: widget.brands,
                value: _brand,
                onChanged: (value) => setState(() => _brand = value),
              ),
            ),
          _FilterSection(
            label: 'Recently updated',
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Only recently updated'),
              value: _recentlyUpdated,
              onChanged: (v) => setState(() => _recentlyUpdated = v),
            ),
          ),
          _FilterSection(
            label: 'Price range',
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Min', isDense: true),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('-'),
                ),
                Expanded(
                  child: TextField(
                    controller: _maxController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Max', isDense: true),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _reset,
                child: const Text('Reset'),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _apply, child: const Text('Apply')),
            ],
          ),
        ],
      ),
    );
  }

  /// Single-choice picker with an explicit "Any" (no filter) option, so
  /// clearing a selection is one tap instead of a hidden gesture.
  Widget _picker({
    required List<String> options,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String?>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Any')),
        for (final option in options)
          DropdownMenuItem<String?>(
            value: option,
            child: Text(option, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }

  /// Clears every picker *and* applies the empty filter in one step, so the
  /// sheet can never display one thing while the list behind it shows another
  /// (Apply would otherwise re-send the stale local selections).
  void _reset() {
    setState(() {
      _availability = null;
      _category = null;
      _brand = null;
      _recentlyUpdated = false;
      _minController.clear();
      _maxController.clear();
    });
    widget.onApply(ProductFilterApplied(search: widget.initial.search));
  }

  void _apply() {
    widget.onApply(ProductFilterApplied(
      search: widget.initial.search,
      stock: widget.initial.stock,
      availability: _availability,
      category: _category,
      brand: _brand,
      recentlyUpdated: _recentlyUpdated,
      minPrice: double.tryParse(_minController.text.trim()),
      maxPrice: double.tryParse(_maxController.text.trim()),
    ));
    Navigator.of(context).pop();
  }
}


class _FilterSection extends StatelessWidget {
  const _FilterSection({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

/// One row's slice of the single card the products list paints — see
/// [LazyCardSliver] in `core/ui/lazy_list.dart`, which owns this chrome so every
/// card-style list in the app keeps the same card look while staying lazy.

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.item,
    required this.showDivider,
    required this.onTap,
    required this.onToggle,
    required this.onUpdateStock,
    required this.onHistory,
  });

  final ShopProductItem item;
  final bool showDivider;
  final VoidCallback onTap;
  final VoidCallback onUpdateStock;
  final VoidCallback onHistory;
  final ValueChanged<bool> onToggle;

  String _lastUpdatedLabel() {
    final updated = item.lastUpdated;
    if (updated == null) return '-';
    final diff = DateTime.now().difference(updated);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 30) return '${diff.inDays} d ago';
    return '${updated.day}/${updated.month}/${updated.year}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stockColor = item.isOutOfStock
        ? AppTheme.rejectedRed
        : item.isLowStock
            ? AppTheme.pendingAmber
            : AppTheme.brandSeed;
    final stockLabel = item.isOutOfStock
        ? 'Out of stock'
        : item.isLowStock
            ? 'Low - ${item.quantity} left'
            : '${item.quantity} in stock';
    final hasImage = item.imageUrl != null && item.imageUrl!.isNotEmpty;

    return Column(
      children: [
        ListTile(
          onTap: onTap,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 48,
              height: 48,
              color: scheme.surfaceContainerHighest,
              child: hasImage
                  ? Image.network(item.imageUrl!,
                      fit: BoxFit.cover,
                      // Decode at roughly 2x the 48px box instead of the
                      // source resolution: a thumbnail never needs the bytes.
                      cacheWidth: 96,
                      // Without this a slow image is an empty grey box, which
                      // reads as "no image" rather than "still loading".
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                              ? child
                              : Center(
                                  child: SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: scheme.outline),
                                  ),
                                ),
                      errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.inventory_2_outlined,
                          size: 22,
                          color: scheme.outline))
                  : Icon(Icons.inventory_2_outlined,
                      size: 22, color: scheme.outline),
            ),
          ),
          title: Text(item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.brand != null && item.brand!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(item.brand!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: scheme.outline)),
              ],
              if (item.variant != null && item.variant!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(item.variant!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: scheme.outline)),
              ],
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.inventory_2_outlined, size: 13, color: stockColor),
                const SizedBox(width: 4),
                Text(stockLabel,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: stockColor)),
                if (item.isStale) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.history_toggle_off,
                      size: 13, color: AppTheme.pendingAmber),
                  const SizedBox(width: 2),
                  Text('stale',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.pendingAmber)),
                ] else if (item.isFresh) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.verified_outlined,
                      size: 13, color: AppTheme.brandSeed),
                  const SizedBox(width: 2),
                  Text('fresh',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.brandSeed)),
                ],
              ]),
              const SizedBox(height: 2),
              Text('Updated ${_lastUpdatedLabel()}',
                  style: TextStyle(fontSize: 11, color: scheme.outline)),
            ],
          ),
          // The trailing slot is height-constrained by ListTile (56px), which
          // the stacked price / MRP / availability switch can exceed — the
          // FittedBox keeps the row overflow-free at every text scale instead
          // of painting the striped overflow banner.
          trailing: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Rs ${item.price.toStringAsFixed(0)}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if (item.mrp != null && item.mrp! > item.price)
                  Text('Rs ${item.mrp!.toStringAsFixed(0)}',
                      style: TextStyle(
                          fontSize: 11,
                          decoration: TextDecoration.lineThrough,
                          color: scheme.outline)),
                const SizedBox(height: 2),
                Switch(
                  value: item.isAvailable,
                  onChanged: onToggle,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
        ),
        // Quick actions: update stock + inspect audit trail (req 25).
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: onUpdateStock,
                icon: const Icon(Icons.edit_note, size: 18),
                label: const Text('Stock'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: onHistory,
                icon: const Icon(Icons.history, size: 18),
                label: const Text('History'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (item.updatedBy != null) ...[
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    'by ${item.updatedBy}',
                    style: TextStyle(
                        fontSize: 11, color: Theme.of(context).colorScheme.outline),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 1, color: Theme.of(context).dividerColor),
      ],
    );
  }
}

/// The "nothing to show" state of the list.
///
/// Three different causes need three different answers. Telling the shopkeeper
/// to "create your first listing" while a filter — not the catalog — is empty
/// would be plainly wrong, so the copy is chosen from what actually emptied
/// the list, and the action clears exactly that.
class _EmptyResults extends StatelessWidget {
  const _EmptyResults({
    required this.catalogIsEmpty,
    required this.search,
    required this.onClear,
  });

  /// True when the shop has no listings at all, not merely no visible ones.
  final bool catalogIsEmpty;

  /// The live search text (empty when a filter alone emptied the list).
  final String search;

  /// Clears the search box and every filter.
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final query = search.trim();
    final (message, action) = catalogIsEmpty
        ? ('No products yet.\nTap "Add" to create your first listing.', null)
        : query.isNotEmpty
            ? ('No products match "$query".', 'Clear search')
            : ('No products match your filters.', 'Clear filters');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            catalogIsEmpty
                ? Icons.inventory_2_outlined
                : Icons.filter_alt_off_outlined,
            size: 40,
            color: scheme.outline,
          ),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.outline)),
          if (action != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onClear, child: Text(action)),
          ],
        ],
      ),
    );
  }
}

class _SummaryChips extends StatelessWidget {
  const _SummaryChips({required this.summary});

  final InventorySummary summary;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SummaryChip(
            label: 'Items',
            value: summary.total.toString(),
            color: Theme.of(context).colorScheme.primary),
        _SummaryChip(
            label: 'In stock',
            value: summary.inStock.toString(),
            color: AppTheme.brandSeed),
        _SummaryChip(
            label: 'Low',
            value: summary.lowStock.toString(),
            color: AppTheme.pendingAmber),
        _SummaryChip(
            label: 'Out',
            value: summary.outOfStock.toString(),
            color: AppTheme.rejectedRed),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip(
      {required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          const SizedBox(width: 6),
          Text(label,
              style:
                  TextStyle(fontSize: 12, color: color.withValues(alpha: 0.9))),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? scheme.onPrimary : scheme.onSurface,
            )),
      ),
    );
  }
}

