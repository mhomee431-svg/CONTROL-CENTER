import 'package:flutter/material.dart';

import '../../../../core/state/system_state.dart';
import '../../../../core/state/system_state_view.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/datetime_utils.dart';
import '../../../products/domain/product_models.dart';
import '../../../products/presentation/controllers/products_controller.dart';

/// Shared presentation helpers for the Inventory module (dashboard, list,
/// stock, history, sync). Every screen reads server vocabulary through these
/// helpers so labels/colors can never drift between screens.

// ── Money ────────────────────────────────────────────────────────────────────

/// Drops the trailing `.0` from whole numbers so `₹120.0` reads as `₹120`.
String trimNumber(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

/// `₹`-prefixed price label, e.g. `₹120` / `₹119.5`.
String moneyLabel(num value) => '₹${trimNumber(value)}';

// ── Inventory source (server vocabulary, display-only mapping) ──────────────

String _humanizeKey(String key) => key
    .split('_')
    .map((p) => p.isEmpty ? p : '${p[0]}${p.substring(1).toLowerCase()}')
    .join(' ');

/// Human label for a server inventory `source` value. Unknown values are
/// humanised instead of throwing, so a new server source still renders.
String inventorySourceLabel(String? source) {
  final key = (source ?? '').trim().toUpperCase();
  return switch (key) {
    '' || 'UNKNOWN' || 'MANUAL' => 'Updated in app',
    'BARCODE_SCAN' => 'Barcode scan',
    'POS_INTEGRATION' => 'POS sync',
    'EXCEL_UPLOAD' => 'Excel import',
    'SYSTEM' => 'System',
    _ => _humanizeKey(key),
  };
}

/// Icon for an inventory source chip.
IconData inventorySourceIcon(String? source) {
  final key = (source ?? '').trim().toUpperCase();
  return switch (key) {
    'BARCODE_SCAN' => Icons.qr_code_scanner_outlined,
    'POS_INTEGRATION' => Icons.point_of_sale_outlined,
    'EXCEL_UPLOAD' => Icons.upload_file_outlined,
    'SYSTEM' => Icons.smart_toy_outlined,
    _ => Icons.edit_outlined,
  };
}

/// Color for an inventory source chip.
Color inventorySourceColor(String? source) {
  final key = (source ?? '').trim().toUpperCase();
  return switch (key) {
    'BARCODE_SCAN' => AppColors.primary,
    'POS_INTEGRATION' => AppColors.orange,
    'EXCEL_UPLOAD' => AppColors.deepGreen,
    'SYSTEM' => AppColors.suspendedGrey,
    _ => AppColors.suspendedGrey,
  };
}

// ── Freshness (server tiers: RECENTLY_UPDATED / FRESH / STALE) ──────────────

/// Shopkeeper-facing freshness label; `null`/unknown renders as `—`.
String freshnessLabel(String? status) {
  final key = (status ?? '').trim().toUpperCase();
  return switch (key) {
    'RECENTLY_UPDATED' || 'FRESH' => 'Fresh',
    'STALE' => 'Needs update',
    _ => '—',
  };
}

/// Color for a freshness chip ([freshnessLabel] owns the wording).
Color freshnessColor(String? status) {
  final key = (status ?? '').trim().toUpperCase();
  if (key == 'RECENTLY_UPDATED' || key == 'FRESH') return AppTheme.verifiedGreen;
  if (key == 'STALE') return AppTheme.pendingAmber;
  return AppTheme.suspendedGrey;
}

// ── Dates ────────────────────────────────────────────────────────────────────

const List<String> _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Compact `12 Jan 2026` formatting (no intl dependency needed here).
String shortDateLabel(DateTime date) =>
    '${date.day} ${_monthNames[date.month - 1]} ${date.year}';

/// Friendly relative label for a last-updated timestamp:
/// `Today 14:05` / `Yesterday` / `12 Jan 2026` / `—` when null.
///
/// This is the EVENT form (when a change happened) used by history and sync
/// lists. Freshness surfaces — "how old is this data?" — use
/// [freshnessChipLabel] / `DateTimeUtils.formatInventoryFreshness` instead, so
/// Inventory, Pricing and POS share one age vocabulary.
String lastUpdatedLabel(DateTime? when) {
  if (when == null) return '—';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(when.year, when.month, when.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) {
    final hh = when.hour.toString().padLeft(2, '0');
    final mm = when.minute.toString().padLeft(2, '0');
    return 'Today $hh:$mm';
  }
  if (diff == 1) return 'Yesterday';
  return shortDateLabel(when);
}

/// Unified freshness-chip copy for inventory rows: the server's tier word
/// plus the shared relative age label, e.g.
/// `Fresh · Inventory updated 5 min ago` / `Needs update · Inventory updated
/// yesterday`. When either half is unknown it drops out instead of stacking
/// dashes.
String freshnessChipLabel(
  String? status,
  DateTime? lastUpdated, {
  DateTime? referenceNow,
}) {
  final tier = freshnessLabel(status);
  if (lastUpdated == null) return tier;
  final age = DateTimeUtils.formatInventoryFreshness(
    lastUpdated,
    referenceNow: referenceNow,
  );
  return tier == '—' ? age : '$tier · $age';
}

// ── Reusable widgets ─────────────────────────────────────────────────────────

/// Small rounded label chip (stock state, freshness, source, offer status).
class InfoChip extends StatelessWidget {
  const InfoChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dashboard stat tile — a big number with a label, tappable.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  final String label;
  final int value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Standard async-state body for screens fed by `productsControllerProvider`:
/// loading spinner / access denied / error + retry, then [builder] with data.
///
/// The rendering itself lives in the shared `SystemStateView` — this class only
/// translates the inventory controller's status into a system state, so the
/// four-way contract and its widgets exist in ONE place across the app.
class ProductsAsyncBody extends StatelessWidget {
  const ProductsAsyncBody({
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
  /// SILENT path (see `ProductsController.refresh` — the rows stay on screen
  /// while fresh ones load), while the first load and Retry keep their
  /// spinner. The body's own scrollable must be always-scrollable for the
  /// gesture to fire on a list shorter than the viewport.
  final Future<void> Function()? onRefresh;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final refresh = onRefresh;
    return SystemStateBody(
      isLoading: status == ProductsStatus.loading,
      failure: switch (status) {
        ProductsStatus.accessDenied => SystemStateSpec.resolve(
          state: SystemState.permissionDenied,
          title: 'Access denied',
          message: message,
          fallbackMessage: "You do not have access to this shop's inventory.",
        ),
        ProductsStatus.error => SystemStateSpec.resolve(
          title: 'Could not load inventory',
          message: message,
          fallbackMessage: 'Please check your connection and retry.',
        ),
        _ => null,
      },
      onRetry: onRetry,
      // The READY body only: a spinner or an error view has nothing to pull.
      builder: refresh == null
          ? builder
          : (context) =>
              RefreshIndicator(onRefresh: refresh, child: builder(context)),
    );
  }
}

/// Pick-one-product list used by Update Stock, Stock History, Update Price
/// and Price History when they are opened without a specific product.
class ProductPickerListView extends StatelessWidget {
  const ProductPickerListView({
    super.key,
    required this.items,
    required this.onSelected,
    this.subtitle,
  });

  final List<ShopProductItem> items;
  final ValueChanged<ShopProductItem> onSelected;

  /// Extra line rendered under each product name (e.g. current stock).
  final String Function(ShopProductItem item)? subtitle;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return SystemStateView.empty(
        title: 'No products yet',
        message: 'Add products or import them from Excel first.',
        icon: Icons.inventory_2_outlined,
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
            subtitle?.call(item) ??
                '${item.stockState.label} · ${item.quantity} units',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onSelected(item),
        );
      },
    );
  }
}

// ── Stock chip ──────────────────────────────────────────────────────────────

/// Color for a [StockStateView] label chip.
///
/// A discontinued listing gets the muted grey: it is deliberately out of play,
/// so it must not borrow the "in stock" green just because units remain.
Color stockStateColor(StockStateView state) {
  if (state.isDiscontinued) return AppTheme.suspendedGrey;
  if (state.isOutOfStock) return AppTheme.rejectedRed;
  if (state.isLowStock) return AppTheme.pendingAmber;
  if (state.isInStock) return AppTheme.verifiedGreen;
  return AppTheme.suspendedGrey;
}
// ── History summary ─────────────────────────────────────────────────────────

/// Net-stock summary tile for the inventory history views.
///
/// Shows the CURRENT stock the server reports, its server-declared stock
/// state, and how many audit entries the trail holds — so the shopkeeper can
/// check the newest movement against the live quantity without leaving the
/// history view.
///
/// Renders nothing when the backend did not send `current_quantity`: a hidden
/// tile is honest, an invented stock number is not.
class StockHistorySummary extends StatelessWidget {
  const StockHistorySummary({
    super.key,
    required this.history,
    this.title = 'Current stock',
  });

  final ProductHistoryResult history;
  final String title;

  @override
  Widget build(BuildContext context) {
    final quantity = history.currentQuantity;
    if (quantity == null) return const SizedBox.shrink();

    final outline = Theme.of(context).colorScheme.outline;
    // Server vocabulary only — never a client-side enum duplicate.
    final state = StockStateView.of(history.stockStatus);
    final color = stockStateColor(state);
    final total = history.total ?? history.entries.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.inventory_2_outlined, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 12, color: outline)),
                Text(
                  '$quantity units · ${state.label}',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: color),
                ),
              ],
            ),
          ),
          Text(
            '$total entr${total == 1 ? 'y' : 'ies'}',
            style: TextStyle(fontSize: 11, color: outline),
          ),
        ],
      ),
    );
  }
}
