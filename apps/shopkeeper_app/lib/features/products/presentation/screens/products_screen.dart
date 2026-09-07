import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../domain/product_models.dart';
import '../controllers/products_controller.dart';
import '../widgets/product_sheets.dart';

/// Inventory overview + product management foundation.
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
        () => ref.read(productsControllerProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(selectedShopProvider, (prev, next) {
      if (prev?.id != next?.id) {
        ref.read(productsControllerProvider.notifier).load();
      }
    });

    final state = ref.watch(productsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Products & inventory')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-product',
        onPressed: state.status == ProductsStatus.ready
            ? () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const ProductCreateSheet(),
                )
            : null,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: SafeArea(
        child: switch (state.status) {
          ProductsStatus.loading =>
            const Center(child: CircularProgressIndicator()),
          ProductsStatus.accessDenied => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.gpp_bad_outlined,
                        size: 64, color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 12),
                    Text(state.message ??
                        'You do not have access to this shop.'),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => context.go('/shops'),
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Switch shop'),
                    ),
                  ],
                ),
              ),
            ),
          ProductsStatus.error => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(state.message ?? 'Could not load inventory.'),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () =>
                        ref.read(productsControllerProvider.notifier).load(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
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

class _ReadyBody extends ConsumerStatefulWidget {
  const _ReadyBody({required this.allItems, required this.summary});

  final List<ShopProductItem> allItems;
  final InventorySummary? summary;

  @override
  ConsumerState<_ReadyBody> createState() => _ReadyBodyState();
}

class _ReadyBodyState extends ConsumerState<_ReadyBody> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

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

  @override
  Widget build(BuildContext context) {
    _message();
    final q = _query.trim().toLowerCase();
    final items = widget.allItems
        .where((i) => q.isEmpty || i.name.toLowerCase().contains(q))
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.summary != null) _SummaryChips(summary: widget.summary!),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Search products…',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text(
                q.isEmpty
                    ? 'No products yet.\nTap “Add” to create your first listing.'
                    : 'No products match “$_query”.',
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
                  ),
              ],
            ),
          ),
        const SizedBox(height: 32),
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
            value: '${summary.total}',
            color: Theme.of(context).colorScheme.primary),
        _SummaryChip(
            label: 'In stock',
            value: '${summary.inStock}',
            color: AppTheme.verifiedGreen),
        _SummaryChip(
            label: 'Low',
            value: '${summary.lowStock}',
            color: AppTheme.pendingAmber),
        _SummaryChip(
            label: 'Out',
            value: '${summary.outOfStock}',
            color: AppTheme.rejectedRed),
        _SummaryChip(
            label: 'Units',
            value: '${summary.totalUnits}',
            color: Colors.blueGrey),
      ],
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.item,
    required this.showDivider,
    this.onTap,
    this.onToggle,
  });

  final ShopProductItem item;
  final bool showDivider;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onToggle;

  Color get _statusColor {
    if (item.isOutOfStock) return AppTheme.rejectedRed;
    if (item.isLowStock) return AppTheme.pendingAmber;
    return AppTheme.verifiedGreen;
  }

  String get _statusLabel {
    if (item.isOutOfStock) return 'Out of stock';
    if (item.isLowStock) return 'Low stock';
    return 'In stock';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [
      ListTile(
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title:
            Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Row(children: [
          Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: _statusColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text('$_statusLabel · qty ${item.quantity}',
              style: TextStyle(fontSize: 12, color: scheme.outline)),
        ]),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('₹${item.price.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              if (item.mrp != null && item.mrp! > item.price)
                Text('₹${item.mrp!.toStringAsFixed(0)}',
                    style: TextStyle(
                        fontSize: 11,
                        decoration: TextDecoration.lineThrough,
                        color: scheme.outline)),
            ],
          ),
          const SizedBox(width: 8),
          Switch(value: item.isAvailable, onChanged: onToggle),
        ]),
      ),
      if (showDivider)
        Divider(height: 1, color: Theme.of(context).dividerColor),
    ]);
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
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(value,
            style: TextStyle(fontWeight: FontWeight.w800, color: color)),
        const SizedBox(width: 6),
        Text(label,
            style:
                TextStyle(fontSize: 12, color: color.withValues(alpha: 0.9))),
      ]),
    );
  }
}

