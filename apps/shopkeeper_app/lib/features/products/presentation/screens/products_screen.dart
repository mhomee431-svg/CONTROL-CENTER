import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../../offers/presentation/controllers/offers_controller.dart';
import '../../../offers/presentation/widgets/offer_create_sheet.dart';
import '../../domain/product_models.dart';
import '../controllers/products_controller.dart';
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
            onPressed: ready ? () => context.push('/inventory-import') : null,
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan barcode',
            onPressed: ready ? () => context.push('/scan-barcode') : null,
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
        child: switch (state.status) {
          ProductsStatus.loading => const Center(
              child: CircularProgressIndicator(),
            ),
          ProductsStatus.accessDenied => _AccessDenied(message: state.message),
          ProductsStatus.error => _ErrorView(
              message: state.message ?? 'Could not load inventory.',
              onRetry: () =>
                  ref.read(productsControllerProvider.notifier).load(),
            ),
          ProductsStatus.ready => RefreshIndicator(
              onRefresh: () =>
                  ref.read(productsControllerProvider.notifier).load(),
              child: _ReadyBody(allItems: state.items, summary: state.summary),
            ),
        },
      ),
    );
  }
}

class _AccessDenied extends StatelessWidget {
  const _AccessDenied({this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.gpp_bad_outlined,
                size: 64, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message ?? 'You do not have access to this shop.',
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => context.go('/shops'),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Switch shop'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
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

  List<ShopProductItem> get _visible {
    final q = _filter.search.trim().toLowerCase();
    var items = widget.allItems.where((i) {
      final nameMatches = q.isEmpty || i.name.toLowerCase().contains(q);
      final brandMatches =
          q.isEmpty || (i.brand ?? '').toLowerCase().contains(q);
      if (!nameMatches && !brandMatches) return false;

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
    return items;
  }

  void _openFilters() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ProductFilterSheet(
        initial: _filter,
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.summary != null) _SummaryChips(summary: widget.summary!),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          onChanged: (v) =>
              setState(() => _filter = _filter.copyWith(search: v)),
          decoration: InputDecoration(
            hintText: 'Search by name or brand…',
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
              child: Text(
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
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text(
                _filter.search.isEmpty
                    ? 'No products yet.\nTap "Add" to create your first listing.'
                    : 'No products match "${_filter.search}".',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  _ProductTile(
                    item: items[i],
                    showDivider: i < items.length - 1,
                    onTap: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => ProductEditSheet(item: items[i]),
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
              ],
            ),
          ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class ProductFilterSheet extends StatefulWidget {
  const ProductFilterSheet({
    super.key,
    required this.initial,
    required this.onApply,
  });

  final ProductFilterApplied initial;
  final ValueChanged<ProductFilterApplied> onApply;

  @override
  State<ProductFilterSheet> createState() => _ProductFilterSheetState();
}

class _ProductFilterSheetState extends State<ProductFilterSheet> {
  final _minController = TextEditingController();
  final _maxController = TextEditingController();
  bool? _availability;
  bool _recentlyUpdated = false;

  @override
  void initState() {
    super.initState();
    _availability = widget.initial.availability;
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
                onPressed: () => widget.onApply(ProductFilterApplied(
                    search: widget.initial.search)),
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

  void _apply() {
    widget.onApply(ProductFilterApplied(
      search: widget.initial.search,
      stock: widget.initial.stock,
      availability: _availability,
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
          trailing: Column(
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
              Switch(value: item.isAvailable, onChanged: onToggle),
            ],
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

