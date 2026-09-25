import 'package:flutter/material.dart';

import '../../../products/domain/product_models.dart';
import '../../../products/presentation/controllers/products_controller.dart';

/// Shared presentation helpers for the Pricing module (price list, update
/// price, price history, offers).

/// Implied discount percent between MRP and selling price, e.g. `20` for a
/// ₹250 MRP selling at ₹200. Returns null when there is no discount.
double? discountPercentOff(double? mrp, double price) {
  if (mrp == null || mrp <= 0 || price <= 0 || price >= mrp) return null;
  final pct = ((mrp - price) / mrp * 100);
  // Round to one decimal; 19.999… becomes 20.
  final rounded = (pct * 10).roundToDouble() / 10;
  return rounded == rounded.roundToDouble()
      ? rounded.roundToDouble()
      : rounded;
}

/// Standard async-state body for pricing screens fed by
/// `productsControllerProvider`.
class PricingAsyncBody extends StatelessWidget {
  const PricingAsyncBody({
    super.key,
    required this.status,
    this.message,
    required this.onRetry,
    this.onRefresh,
    required this.builder,
  });

  final ProductsStatus status;
  final String? message;
  final VoidCallback onRetry;

  /// When set, the READY body is wrapped in a [RefreshIndicator]: pull is the
  /// SILENT path (the rows stay on screen while fresh ones load), while the
  /// first load and Retry keep their spinner.
  final Future<void> Function()? onRefresh;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final refresh = onRefresh;
    return switch (status) {
      ProductsStatus.loading =>
        const Center(child: CircularProgressIndicator()),
      ProductsStatus.accessDenied ||
      ProductsStatus.error =>
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  status == ProductsStatus.accessDenied
                      ? Icons.lock_outline
                      : Icons.error_outline,
                  size: 40,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 12),
                Text(
                  status == ProductsStatus.accessDenied
                      ? 'Access denied'
                      : 'Could not load products',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  message ?? 'Please check your connection and retry.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                    onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      ProductsStatus.ready => refresh == null
          ? builder(context)
          : RefreshIndicator(onRefresh: refresh, child: builder(context)),
    };
  }
}

/// Pick-one-product list shared by Update Price and Price History when they
/// are opened without a specific product.
class PricingProductPicker extends StatelessWidget {
  const PricingProductPicker({
    super.key,
    required this.items,
    required this.onSelected,
  });

  final List<ShopProductItem> items;
  final ValueChanged<ShopProductItem> onSelected;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 40, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              const Text('No products yet'),
              const SizedBox(height: 4),
              Text(
                'Add products or import them from Excel first.',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final item = items[i];
        return ListTile(
          title: Text(item.name),
          subtitle: Text(
            'Current price ₹${_trim(item.price)}'
            '${item.mrp == null ? '' : ' · MRP ₹${_trim(item.mrp!)}'}',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onSelected(item),
        );
      },
    );
  }
}

String _trim(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}
