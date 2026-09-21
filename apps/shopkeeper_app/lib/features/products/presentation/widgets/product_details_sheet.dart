import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/product_models.dart';
import '../controllers/products_controller.dart';
import 'product_sheets.dart';
import 'stock_sheets.dart';

/// Read-only **Product Details** view for one shop listing.
///
/// This is the tap target of every product row: it answers "what exactly is
/// this listing?" *before* the shopkeeper changes anything. Every write stays
/// in [ProductEditSheet] / [StockUpdateSheet] / [ProductHistorySheet], which
/// are launched from here — so viewing a product can never accidentally
/// mutate it.
///
/// The sheet watches [productsControllerProvider] and re-resolves the row by
/// id instead of rendering the tapped snapshot, so after an edit lands (the
/// controller swaps the item in place) the details refresh automatically.
class ProductDetailsSheet extends ConsumerWidget {
  const ProductDetailsSheet({super.key, required this.item});

  /// The row that was tapped. Used for its id; the live values are re-read
  /// from controller state on every build.
  final ShopProductItem item;

  /// Master-catalog fields are read-only references — the shopkeeper owns the
  /// shop-specific association (price / stock / availability) only.
  static const _masterReferenceNote =
      'Brand, category and image come from the product catalog. Change the '
      'listing price, stock and availability here.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(productsControllerProvider).itemById(item.id) ??
        // The row left the catalog (or the list has not loaded yet): the
        // tapped snapshot is still the best answer, and the sheet stays
        // readable instead of throwing.
        item;
    final scheme = Theme.of(context).colorScheme;
    final discount = _discountPercent(current);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              _DetailsHeader(item: current),
              const SizedBox(height: 16),
              _AvailabilityRow(item: current),
              _DetailSection(
                title: 'Pricing',
                rows: [
                  ('Selling price', 'Rs ${current.price.toStringAsFixed(2)}'),
                  if (current.mrp != null && current.mrp! > 0)
                    ('MRP', 'Rs ${current.mrp!.toStringAsFixed(2)}'),
                  if (discount != null) ('Discount', '$discount% off MRP'),
                ],
              ),
              _DetailSection(
                title: 'Inventory',
                rows: [
                  ('Quantity', '${current.quantity}'),
                  ('Stock status', current.stockState.label),
                  ('Last updated', _lastUpdatedLabel(current.lastUpdated)),
                  ('Updated by', current.updatedBy ?? 'Not recorded'),
                  ('Source', _sourceLabel(current.source)),
                  if (current.hasFreshness)
                    (
                      'Data freshness',
                      current.isStale ? 'Stale - needs a refresh' : 'Fresh',
                    ),
                ],
              ),
              _DetailSection(
                title: 'Catalog reference',
                rows: [
                  ('Listing status', current.isActive ? 'Active' : 'Inactive'),
                  ('SKU', current.sku ?? 'Not set'),
                  ('Brand', current.brand ?? 'Not set'),
                  ('Category', current.category ?? 'Not set'),
                  ('Variant', current.variant ?? 'Not set'),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          _open(context, ProductEditSheet(item: current)),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit product'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _open(context, StockUpdateSheet(item: current)),
                      icon: const Icon(Icons.exposure_plus_1, size: 18),
                      label: const Text('Update stock'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton.icon(
                  onPressed: () =>
                      _open(context, ProductHistorySheet(item: current)),
                  icon: const Icon(Icons.history, size: 18),
                  label: const Text('View history'),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _masterReferenceNote,
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens a follow-up sheet **on top of** these details (rather than closing
  /// them first) so the shopkeeper lands back on the refreshed details.
  void _open(BuildContext context, Widget sheet) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => sheet,
    );
  }
}

/// Percentage saved against MRP, or null when there is no real discount.
int? _discountPercent(ShopProductItem item) {
  final mrp = item.mrp;
  if (mrp == null || mrp <= 0 || mrp <= item.price) return null;
  return (((mrp - item.price) / mrp) * 100).round();
}

/// Inventory source reported by the backend (MANUAL / BARCODE_SCAN / ...).
String _sourceLabel(String? source) => switch (source) {
      'MANUAL' => 'Manual entry',
      'BARCODE_SCAN' => 'Barcode scan',
      'EXCEL_UPLOAD' || 'IMPORT' => 'Bulk import',
      'POS_INTEGRATION' || 'POS_SYNC' => 'POS sync',
      'SYSTEM' => 'System',
      _ => 'Not recorded',
    };

/// Relative "Updated ..." label; never invents a timestamp when the backend
/// did not provide one.
String _lastUpdatedLabel(DateTime? updated) {
  if (updated == null) return 'Not updated yet';
  final diff = DateTime.now().difference(updated);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays < 30) return '${diff.inDays} d ago';
  return '${updated.day}/${updated.month}/${updated.year}';
}

/// Image / name / status chips at the top of the details sheet.
class _DetailsHeader extends StatelessWidget {
  const _DetailsHeader({required this.item});

  final ShopProductItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasImage = item.imageUrl != null && item.imageUrl!.isNotEmpty;
    final subtitle = [
      if (item.brand != null && item.brand!.isNotEmpty) item.brand!,
      if (item.variant != null && item.variant!.isNotEmpty) item.variant!,
    ].join(' - ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 72,
            height: 72,
            color: scheme.surfaceContainerHighest,
            child: hasImage
                ? Image.network(
                    item.imageUrl!,
                    // Decorative — the product name sits right next to it.
                    excludeFromSemantics: true,
                    fit: BoxFit.cover,
                    cacheWidth: 144,
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                            ? child
                            : const Center(
                                child: SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              ),
                    errorBuilder: (context, error, stackTrace) =>
                        _ImagePlaceholder(color: scheme.outline, label: 'Image'),
                  )
                : _ImagePlaceholder(color: scheme.outline, label: 'No image'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(subtitle,
                    style: TextStyle(fontSize: 12, color: scheme.outline)),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _StatusChip(
                    label: item.isActive ? 'Active' : 'Inactive',
                    color:
                        item.isActive ? AppTheme.verifiedGreen : scheme.outline,
                  ),
                  _StatusChip(
                    label: item.isAvailable ? 'Available' : 'Hidden',
                    color: item.isAvailable
                        ? AppTheme.brandSeed
                        : AppTheme.pendingAmber,
                  ),
                  if (item.isOutOfStock)
                    const _StatusChip(
                        label: 'Out of stock', color: AppTheme.rejectedRed)
                  else if (item.isLowStock)
                    const _StatusChip(
                        label: 'Low stock', color: AppTheme.pendingAmber),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Explicit placeholder so "no image" is a deliberate state, not a blank box.
class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.image_not_supported_outlined, size: 20, color: color),
        const SizedBox(height: 2),
        Text(label, style: AppTypography.caption.copyWith(color: color)),
      ],
    );
  }
}

/// Small pill for a listing state (Active / Available / stock tier).
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

/// Availability toggle — the one write this sheet performs directly, because
/// hiding/showing a listing is a single boolean handled by the controller's
/// optimistic update (the same path as the list row switch).
class _AvailabilityRow extends ConsumerWidget {
  const _AvailabilityRow({required this.item});

  final ShopProductItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: SwitchListTile(
        value: item.isAvailable,
        onChanged: (value) => ref
            .read(productsControllerProvider.notifier)
            .setAvailability(item.id, value),
        title: const Text('Available to customers',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(
          item.isAvailable
              ? 'Customers can see and buy this listing.'
              : 'Hidden from customers until you switch it back on.',
          style: TextStyle(fontSize: 12, color: scheme.outline),
        ),
      ),
    );
  }
}

/// Label/value block inside the details sheet.
class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary),
        ),
        const SizedBox(height: 8),
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(label,
                      style: TextStyle(fontSize: 13, color: scheme.outline)),
                ),
                Expanded(
                  child: Text(value,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}