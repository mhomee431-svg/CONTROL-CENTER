import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/numeric_input.dart';
import '../../../inventory/presentation/widgets/inventory_shared.dart';
import '../../domain/product_models.dart';
import '../controllers/products_controller.dart';

/// Guard rails for stock quantities (mirrors the backend's authority — the
/// client validates only to fail fast; the server re-checks everything).
const int _maxQuantity = 999999;

/// Humanises an inventory source value from the server
/// (MANUAL → Manual, BARCODE_SCAN → Barcode, POS_INTEGRATION → POS …).
String sourceLabel(String? source) => switch ((source ?? '').toUpperCase()) {
      'MANUAL' => 'Manual',
      'BARCODE_SCAN' => 'Barcode',
      'EXCEL_UPLOAD' => 'Excel',
      'POS_INTEGRATION' => 'POS',
      'SYSTEM' => 'System',
      '' => '—',
      final raw => raw[0] + raw.substring(1).toLowerCase().replaceAll('_', ' '),
    };

String _relativeTime(DateTime? time) {
  if (time == null) return '—';
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays < 30) return '${diff.inDays} d ago';
  return '${time.day}/${time.month}/${time.year}';
}


/// "Update stock" bottom sheet (req 25).
///
/// Shows the product, its current stock and the last update metadata
/// (when / by whom / from which source — all server values), then applies a
/// **delta** change through the backend audit-trail endpoint. The backend
/// stays authoritative: on success the sheet closes and the controller swaps
/// in the server-computed quantity; on rejection the backend's readable
/// error is surfaced verbatim.
class StockUpdateSheet extends ConsumerStatefulWidget {
  const StockUpdateSheet({super.key, required this.item});

  final ShopProductItem item;

  @override
  ConsumerState<StockUpdateSheet> createState() => _StockUpdateSheetState();
}

class _StockUpdateSheetState extends ConsumerState<StockUpdateSheet> {
  late final TextEditingController _input;
  bool _saving = false;
  String? _error;

  int get _current => widget.item.quantity;

  /// Target quantity parsed from the input; null when not a valid int.
  int? get _target {
    final text = _input.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  /// Signed change this sheet would apply (new − current); null when the
  /// input is not a valid quantity.
  int? get _delta {
    final t = _target;
    return t == null ? null : t - _current;
  }

  /// Client-side pre-flight validation. Returns null when the pending change
  /// is valid, otherwise a shopkeeper-readable reason it cannot be saved.
  String? get _validationError {
    final text = _input.text.trim();
    final t = _target;
    if (text.isEmpty || t == null) return 'Enter a valid whole number';
    if (t < 0) return 'Stock cannot be negative';
    if (t > _maxQuantity) return 'Quantity cannot exceed $_maxQuantity';
    return null;
  }

  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: '${widget.item.quantity}');
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _bump(int by) {
    final t = _target ?? _current;
    final next = (t + by).clamp(0, _maxQuantity);
    _input.text = '$next';
    setState(() => _error = null);
  }

  Future<void> _save() async {
    // Duplicate-submission guard: one in-flight request at a time.
    if (_saving) return;
    final error = _validationError;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final delta = _delta!;
    if (delta == 0) return; // nothing to save — CTA is disabled anyway

    setState(() {
      _saving = true;
      _error = null;
    });

    final outcome = await ref
        .read(productsControllerProvider.notifier)
        .adjustStock(productId: widget.item.id, delta: delta);

    if (!mounted) return;
    if (outcome.ok) {
      Navigator.of(context).pop();
    } else {
      // Backend rejection (or offline) — surface the readable message.
      setState(() {
        _saving = false;
        _error = outcome.error ?? 'Could not update stock. Please retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final error = _error ?? _validationError;
    final delta = _delta;
    final canSave = !_saving && error == null && delta != null && delta != 0;
    final stock = widget.item.stockState;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(appText(context).commonUpdateStock4, style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(appText(context).stockSheetsCurrentStockCurrent(_current),
                        style: TextStyle(fontSize: 13, color: scheme.outline)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: stock.isOutOfStock
                      ? scheme.errorContainer
                      : scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  stock.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: stock.isOutOfStock
                        ? scheme.onErrorContainer
                        : scheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            appText(context).stockSheetsLastUpdatedValueValue2Value3(_relativeTime(widget.item.lastUpdated), widget.item.updatedBy != null ? ' · by ${widget.item.updatedBy}' : '', sourceLabel(widget.item.source)),
            style: TextStyle(fontSize: 12, color: scheme.outline),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Minus — clamped at 0, never negative.
              IconButton.outlined(
                onPressed: _saving ? null : () => _bump(-1),
                icon: const Icon(Icons.remove),
                tooltip: appText(context).commonDecrease,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _input,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: NumericInput.whole(),
                  // The sheet's own max-quantity guard rejects above
                  // _maxQuantity, so the cap here only stops absurd input.
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  decoration: InputDecoration(
                    labelText: appText(context).commonNewQuantity,
                    isDense: true,
                    errorText: error,
                  ),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 12),
              // Plus — clamped at the max quantity guard.
              IconButton.outlined(
                onPressed: _saving ? null : () => _bump(1),
                icon: const Icon(Icons.add),
                tooltip: appText(context).commonIncrease,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            delta == null || error != null
                ? ''
                : delta > 0
                    ? 'Will add $delta units'
                    : delta < 0
                        ? 'Will remove ${-delta} units'
                        : 'No change',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.outline),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            // Disabled while saving (duplicate-submission guard), when the
            // input is invalid, or when the change is a no-op.
            onPressed: canSave ? _save : null,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving…' : 'Save Stock'),
          ),
        ],
      ),
    );
  }
}


/// "Inspect history" bottom sheet — the product's full inventory audit trail
/// (movements, adjustments and price changes, newest first, as reported by
/// the backend `GET …/history` endpoint).
class ProductHistorySheet extends ConsumerStatefulWidget {
  const ProductHistorySheet({super.key, required this.item});

  final ShopProductItem item;

  @override
  ConsumerState<ProductHistorySheet> createState() =>
      _ProductHistorySheetState();
}

class _ProductHistorySheetState extends ConsumerState<ProductHistorySheet> {
  ProductHistoryLoad? _load;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final load = await ref
        .read(productsControllerProvider.notifier)
        .loadHistory(widget.item.id);
    if (mounted) {
      setState(() {
        _load = load;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(appText(context).stockSheetsHistoryName(widget.item.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              appText(context).stockSheetsStockMovementsAdjustmentsAndPrice,
              style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : (_load?.ok ?? false)
                      ? _HistoryList(history: _load!.history!, onRefresh: _fetch)
                      : Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Column(
                            children: [
                              Text(
                                _load?.error ?? 'Could not load history.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                  onPressed: _fetch,
                                  child: Text(appText(context).commonRetry7)),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}


class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.history, required this.onRefresh});

  final ProductHistoryResult history;

  /// Re-fetches the trail (pull-to-refresh). Owned by the sheet so the summary
  /// tile and the entries always come from the same fetch.
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Always scrollable so pull-to-refresh works even with an empty trail.
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        shrinkWrap: true,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          // Net current stock the server reports, so the newest movement can
          // be checked against the live quantity at a glance.
          StockHistorySummary(history: history),
          if (history.entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(appText(context).commonNoHistoryRecordedYet,
                    style: TextStyle(color: theme.colorScheme.outline)),
              ),
            )
          else
            for (var i = 0; i < history.entries.length; i++)
              _HistoryTile(
                entry: history.entries[i],
                isLast: i == history.entries.length - 1,
              ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry, required this.isLast});

  final ProductHistoryEntry entry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final (icon, title, detail, color) = switch (entry.type) {
      'adjustment' => (
          Icons.tune_outlined,
          entry.adjustmentType ?? 'Adjustment',
          _adjustmentDetail(),
          (entry.quantityAdjustment ?? 0) > 0
              ? AppTheme.brandSeed
              : AppTheme.pendingAmber,
        ),
      'price_change' => (
          Icons.sell_outlined,
          'Price change',
          _priceDetail(),
          scheme.primary,
        ),
      _ => (
          Icons.swap_vert_outlined,
          entry.movementType ?? 'Movement',
          _movementDetail(),
          (entry.stockDelta ?? 0) >= 0
              ? AppTheme.brandSeed
              : AppTheme.pendingAmber,
        ),
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Icon(icon, size: 18, color: color),
              if (!isLast)
                Expanded(
                  child: Container(width: 1.5, color: scheme.outlineVariant),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                      ),
                      if (entry.stockDelta != null)
                        Text(
                          appText(context).stockSheetsValueStockDelta(
                    entry.stockDelta! > 0 ? '+' : '', '${entry.stockDelta}'),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: entry.stockDelta! > 0
                                ? AppTheme.brandSeed
                                : entry.stockDelta! < 0
                                    ? AppTheme.pendingAmber
                                    : scheme.outline,
                          ),
                        ),
                    ],
                  ),
                  if (detail != null)
                    Text(detail,
                        style: TextStyle(fontSize: 12, color: scheme.outline)),
                  Text(
                    appText(context).stockSheetsValueValue2ActorLabel(_relativeTime(entry.occurredAt), entry.source != null ? ' · ${sourceLabel(entry.source)}' : '', entry.actorLabel),
                    style: TextStyle(fontSize: 11, color: scheme.outline),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _movementDetail() {
    final before = entry.quantityBefore;
    final after = entry.quantityAfter;
    if (before == null && after == null) return entry.notes;
    return '$before → $after'
        '${entry.notes != null && entry.notes!.isNotEmpty ? ' · ${entry.notes}' : ''}';
  }

  String? _adjustmentDetail() {
    final parts = <String>[];
    if (entry.reason != null && entry.reason!.isNotEmpty) {
      parts.add(entry.reason!);
    }
    if (entry.notes != null && entry.notes!.isNotEmpty) {
      parts.add(entry.notes!);
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String? _priceDetail() {
    final oldP = entry.oldPrice;
    final newP = entry.newPrice;
    if (oldP == null && newP == null) return null;
    String fmt(double? v) => v == null ? '—' : 'Rs ${v.toStringAsFixed(0)}';
    return '${fmt(oldP)} → ${fmt(newP)}'
        '${entry.changeSource != null ? ' · ${sourceLabel(entry.changeSource)}' : ''}';
  }
}

