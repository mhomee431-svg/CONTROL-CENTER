import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/datetime_utils.dart';
import '../../../inventory/presentation/widgets/inventory_shared.dart';
import '../../domain/product_models.dart';
import '../controllers/products_controller.dart';
import 'product_image_view.dart';
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
                    borderRadius: AppRadius.xsBorder,
                  ),
                ),
              ),
              _DetailsHeader(item: current),
              const SizedBox(height: 16),
              _AvailabilityRow(item: current),
              const SizedBox(height: 12),
              _ListingLifecycleRow(item: current),
              _DetailSection(
                title: appText(context).commonPricing,
                rows: [
                  ('Selling price', 'Rs ${current.price.toStringAsFixed(2)}'),
                  if (current.mrp != null && current.mrp! > 0)
                    ('MRP', 'Rs ${current.mrp!.toStringAsFixed(2)}'),
                  if (discount != null) ('Discount', '$discount% off MRP'),
                ],
              ),
              _DetailSection(
                title: appText(context).commonInventory3,
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
                title: appText(context).commonCatalogReference,
                rows: [
                  // Reads the reconciled listing state, not `is_active` alone:
                  // after a deactivate the server leaves `is_active` true, so
                  // this used to print "Active" for a listing the Discontinued
                  // slice was simultaneously calling discontinued.
                  ('Listing status', current.listingState.label),
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
                      label: Text(appText(context).commonEditProduct),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _open(context, StockUpdateSheet(item: current)),
                      icon: const Icon(Icons.exposure_plus_1, size: 18),
                      label: Text(appText(context).commonUpdateStock3),
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
                  label: Text(appText(context).commonViewHistory3),
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
///
/// Delegates to the shared label rather than keeping a fourth wording: this
/// screen used to say "Barcode scan" while the inventory list said "Updated via
/// barcode" for the same fact, and a shopkeeper cannot act on two versions of
/// it. `inventorySourceLabel` also understands `IMPORT` and `POS_SYNC`, the two
/// spellings this private switch had to special-case.
String _sourceLabel(String? source) => inventorySourceLabel(source);

/// Relative "Updated ..." label; never invents a timestamp when the backend
/// did not provide one.
String _lastUpdatedLabel(DateTime? updated) =>
    DateTimeUtils.formatRelativeOrLocal(updated, nullLabel: 'Not updated yet');

/// Image / name / status chips at the top of the details sheet.
class _DetailsHeader extends StatelessWidget {
  const _DetailsHeader({required this.item});

  final ShopProductItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subtitle = [
      if (item.brand != null && item.brand!.isNotEmpty) item.brand!,
      if (item.variant != null && item.variant!.isNotEmpty) item.variant!,
    ].join(' - ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Shared resilient image: it owns the placeholder / loading / broken
        // states so a dead presigned URL degrades to the same box everywhere
        // instead of an inconsistent one-off fallback.
        ProductImageView(
          imageUrl: item.imageUrl,
          width: 72,
          height: 72,
          borderRadius: AppRadius.smBorder,
          // Decorative — the product name sits right next to it.
          excludeFromSemantics: true,
          cacheWidth: 144,
          placeholderWidget:
              _ImagePlaceholder(color: scheme.outline, label: appText(context).commonNoImage),
          errorWidget: _ImagePlaceholder(color: scheme.outline, label: appText(context).commonImage),
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
                    // Same reconciled view as the "Listing status" row, so
                    // the chip can never claim "Active" for a listing the
                    // body below calls discontinued.
                    label: item.listingState.label,
                    color: item.listingState.isActive
                        ? AppTheme.verifiedGreen
                        : AppTheme.suspendedGrey,
                  ),
                  _StatusChip(
                    label: item.isAvailable ? 'Available' : 'Hidden',
                    color: item.isAvailable
                        ? AppTheme.brandSeed
                        : AppTheme.pendingAmber,
                  ),
                  if (item.isOutOfStock)
                    _StatusChip(
                        label: appText(context).commonOutOfStock3, color: AppTheme.rejectedRed)
                  else if (item.isLowStock)
                    _StatusChip(
                        label: appText(context).commonLowStock5, color: AppTheme.pendingAmber),
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
        borderRadius: AppRadius.xsBorder,
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
        title: Text(appText(context).commonAvailableToCustomers,
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

/// Deactivate / re-activate a listing (spec §74 destructive actions, §75
/// delete-vs-deactivate).
///
/// This is the only destructive write the products module offers, and it is
/// deliberately NOT a delete: `ShopProduct` carries a `SoftDeleteMixin`, so
/// deactivating withdraws the listing from customers while its price and
/// inventory history stay intact for reports — exactly the "prefer
/// Deactivate/Archive when historical data must remain" rule.
///
/// [_busy] lives here rather than in the controller because it is per-open-sheet
/// UI state (a spinner on the button, §76), while the resulting status is a
/// catalog fact that lands in `ProductsState` through `setListingStatus`.
class _ListingLifecycleRow extends ConsumerStatefulWidget {
  const _ListingLifecycleRow({required this.item});

  final ShopProductItem item;

  @override
  ConsumerState<_ListingLifecycleRow> createState() =>
      _ListingLifecycleRowState();
}

class _ListingLifecycleRowState extends ConsumerState<_ListingLifecycleRow> {
  bool _busy = false;

  /// One sentence explaining what the CURRENT state means, so the shopkeeper
  /// never has to guess whether their history survives.
  String _description(ListingStateView state) => switch (state.value) {
        'DISCONTINUED' =>
          'Discontinued - hidden from customers. History is kept, so your '
              'reports stay accurate.',
        'INACTIVE' => 'Inactive - not published to customers yet.',
        _ => 'Published - customers can find this listing in your shop.',
      };

  Future<void> _confirmDeactivate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Deactivate this product?'),
        // §74: a destructive action must "explain impact clearly". The name is
        // in the sentence on purpose — the sheet behind it scrolls, and the
        // dialog is the only thing guaranteed to be read.
        content: Text(
          '"${widget.item.name}" will stop appearing in search and customer '
          'results. Its price history and stock records are kept, so your '
          'reports stay intact. Nothing is deleted - you can reactivate it at '
          'any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_deactivate_product'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _apply(ListingStateView.discontinued, 'Product deactivated');
  }

/// Runs the write and reports the outcome. Never closes the sheet: a refused
  /// write must leave the shopkeeper looking at the listing they were working
  /// on, and must never be announced as a success.
  Future<void> _apply(ListingStateView next, String successMessage) async {
    setState(() => _busy = true);
    final ok = await ref
        .read(productsControllerProvider.notifier)
        .setListingStatus(widget.item.id, next);
    if (!mounted) return;
    setState(() => _busy = false);

    // The backend's own wording whenever there is one — an offline write must
    // not be laundered into a generic "Update failed. Please retry."
    final failure = ref.read(productsControllerProvider).message;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(failure ??
              (ok ? successMessage : 'Update failed. Please retry.')),
          backgroundColor: ok ? null : Theme.of(context).colorScheme.error,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = widget.item.listingState;
    final withdrawn = !state.isActive;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Listing status',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                if (_busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _description(state),
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: withdrawn
                  ? TextButton.icon(
                      key: const Key('product-reactivate'),
                      onPressed: _busy
                          ? null
                          : () => _apply(
                              ListingStateView.active, 'Product reactivated'),
                      icon: const Icon(Icons.restore, size: 18),
                      label: const Text('Reactivate product'),
                    )
                  : TextButton.icon(
                      key: const Key('product-deactivate'),
                      onPressed: _busy ? null : _confirmDeactivate,
                      icon: const Icon(Icons.archive_outlined, size: 18),
                      label: const Text('Deactivate product'),
                      style:
                          TextButton.styleFrom(foregroundColor: scheme.error),
                    ),
            ),
          ],
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
