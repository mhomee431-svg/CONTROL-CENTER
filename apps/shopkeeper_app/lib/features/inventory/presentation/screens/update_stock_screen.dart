import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/validation/field_rules.dart';
import '../../../../core/ui/numeric_input.dart';
import '../../../products/domain/product_models.dart';
import '../../../products/presentation/controllers/products_controller.dart';
import '../widgets/inventory_shared.dart';

/// The adjustment types offered for a stock correction. The backend accepts
/// any short string; these are the audit-trail labels shopkeepers use.
const List<String> kStockAdjustmentTypes = [
  'CORRECTION',
  'RESTOCK',
  'RETURN',
  'DAMAGE',
  'SPOILAGE',
];

/// Update Stock — records a **delta** stock change for one product through the
/// backend audit-trail endpoint. The server returns the new quantity and stock
/// state; the client never does its own arithmetic.
///
/// Opened either with a product (from the inventory list) or without one —
/// then a product picker is shown first.
class UpdateStockScreen extends ConsumerStatefulWidget {
  const UpdateStockScreen({super.key, this.product});

  final ShopProductItem? product;

  @override
  ConsumerState<UpdateStockScreen> createState() => _UpdateStockScreenState();
}

class _UpdateStockScreenState extends ConsumerState<UpdateStockScreen> {
  ShopProductItem? _selected;
  final _deltaController = TextEditingController();
  final _reasonController = TextEditingController();
  String _adjustmentType = 'CORRECTION';
  bool _saving = false;
  String? _error;

  /// Live validation for the quantity field, shown as soon as the shopkeeper
  /// types rather than after a failed save.
  ///
  /// Null until the field is touched, so an untouched form does not open with
  /// a red box telling someone what they have not typed yet.
  String? _deltaError;

  /// Success payload from the last save (drives the confirmation panel).
  StockAdjustmentResult? _result;

  bool get _pickerMode => widget.product == null && _selected == null;

  @override
  void initState() {
    super.initState();
    _selected = widget.product;
    Future.microtask(() {
      final state = ref.read(productsControllerProvider);
      if (_pickerMode &&
          state.status == ProductsStatus.loading &&
          state.items.isEmpty) {
        ref.read(productsControllerProvider.notifier).load();
      }
    });
  }

  @override
  void dispose() {
    _deltaController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  ShopProductItem get _product => _selected ?? widget.product!;

  Future<void> _applyDelta(int delta) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
      _result = null;
    });
    final outcome =
        await ref.read(productsControllerProvider.notifier).adjustStock(
              productId: _product.id,
              delta: delta,
              adjustmentType: _adjustmentType,
              reason: _reasonController.text.trim().isEmpty
                  ? null
                  : _reasonController.text.trim(),
            );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (outcome.ok) {
        _result = outcome.result;
        _deltaController.clear();
        _reasonController.clear();
      } else {
        _error = outcome.error;
      }
    });
  }

  /// Re-run the same rule the server will run, on every keystroke.
  ///
  /// The message is the shared one so the app and the backend cannot word the
  /// same mistake differently — the shopkeeper reads one sentence whether the
  /// answer arrives here or from the server.
  void _onDeltaChanged(String value) {
    setState(() => _deltaError = stockDelta(value));
  }

  void _submit() {
    final message = stockDelta(_deltaController.text);
    if (message != null) {
      // Already visible inline once the field has been touched; this also
      // covers submitting an untouched empty form.
      setState(() {
        _deltaError = message;
        _error = message;
      });
      return;
    }
    _applyDelta(int.parse(_deltaController.text.trim()));
  }

  void _bump(int delta) {
    final current = int.tryParse(_deltaController.text.trim()) ?? 0;
    _deltaController.text = '${current + delta}';
    // A chip press is a deliberate change: validate it like a keystroke.
    _onDeltaChanged(_deltaController.text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(productsControllerProvider);

    if (_pickerMode) {
      return Scaffold(
        appBar: AppBar(title: Text(appText(context).commonUpdateStock2)),
        body: ProductsAsyncBody(
          status: state.status,
          message: state.message,
          onRetry: () => ref.read(productsControllerProvider.notifier).load(),
          builder: (context) => ProductPickerListView(
            items: state.items,
            onSelected: (item) => setState(() => _selected = item),
          ),
        ),
      );
    }

    final product = _product;
    final stock = product.stockState;

    return Scaffold(
      appBar: AppBar(
        title: Text(appText(context).commonUpdateStock2),
        actions: [
          if (widget.product == null)
            IconButton(
              tooltip: appText(context).commonChooseAnotherProduct2,
              icon: const Icon(Icons.swap_horiz_outlined),
              onPressed: () => setState(() {
                _selected = null;
                _result = null;
                _error = null;
              }),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ProductHeader(product: product, stock: stock),
          const SizedBox(height: 16),
          if (_result != null) ...[
            _ResultPanel(result: _result!),
            const SizedBox(height: 16),
          ],
          _Form(
            deltaController: _deltaController,
            reasonController: _reasonController,
            adjustmentType: _adjustmentType,
            saving: _saving,
            error: _error,
            deltaError: _deltaError,
            onDeltaChanged: _onDeltaChanged,
            onTypeChanged: (v) =>
                setState(() => _adjustmentType = v ?? 'CORRECTION'),
            onBump: _saving ? null : _bump,
            onSubmit: _submit,
          ),
        ],
      ),
    );
  }
}

class _ProductHeader extends StatelessWidget {
  const _ProductHeader({required this.product, required this.stock});

  final ShopProductItem product;
  final StockStateView stock;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(product.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              appText(context).updateStockScreenCurrentQuantityUnits(product.quantity),
              key: const Key('update-stock-current'),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 6),
            InfoChip(label: stock.label, color: stockStateColor(stock)),
          ],
        ),
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.result});

  final StockAdjustmentResult result;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('update-stock-result'),
      margin: EdgeInsets.zero,
      color: AppTheme.verifiedGreen.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdBorder,
        side: BorderSide(color: AppTheme.verifiedGreen.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: AppTheme.verifiedGreen),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appText(context).updateStockScreenStockUpdatedPreviousQuantityNewQuantityUnits(result.previousQuantity, result.newQuantity, StockStateView.of(result.stockStatus).label),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  // Spec: "Show: Last Updated, Source, Freshness." Reuses the
                  // shared inventory helpers so this panel cannot drift from the
                  // list and sync-status screens that name the same three things.
                  //
                  // Omitted entirely when the server sent none of the three: an
                  // older payload should stay quiet rather than print three
                  // "Unknown"s under a success tick.
                  if (result.source != null ||
                      result.freshnessStatus != null ||
                      result.lastInventoryUpdate != null)
                    Text(
                      [
                        inventorySourceLabel(result.source),
                        freshnessLabel(result.freshnessStatus),
                        lastUpdatedLabel(result.lastInventoryUpdate),
                      ].join('  ·  '),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({
    required this.deltaController,
    required this.reasonController,
    required this.adjustmentType,
    required this.saving,
    required this.error,
    required this.onTypeChanged,
    required this.onBump,
    required this.onSubmit,
    this.deltaError,
    this.onDeltaChanged,
  });

  final TextEditingController deltaController;
  final TextEditingController reasonController;
  final String adjustmentType;
  final bool saving;
  final String? error;
  final ValueChanged<String?> onTypeChanged;
  final ValueChanged<int>? onBump;
  final VoidCallback onSubmit;

  /// Live message for the quantity field (null until the field is touched).
  final String? deltaError;
  final ValueChanged<String>? onDeltaChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(appText(context).commonQuantityChange,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              key: const Key('update-stock-delta'),
              controller: deltaController,
              keyboardType:
                  const TextInputType.numberWithOptions(signed: true),
              // Deltas are whole numbers that may be negative (`-3` removes
              // stock); the minus is only accepted in the leading position.
              inputFormatters: NumericInput.signedWhole(),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              // Immediate feedback: the rule runs per keystroke, so a
              // fractional or zero change is refused before Save is pressed.

              onChanged: onDeltaChanged,
              decoration: InputDecoration(
                hintText: appText(context).updateStockScreenEG24ToAdd,
                errorText: deltaError,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final d in const [1, 5, 10, -1, -5, -10])
                  ActionChip(
                    key: Key('update-stock-bump-$d'),
                    label: Text(d > 0 ? '+$d' : '$d'),
                    onPressed: onBump == null ? null : () => onBump!(d),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(appText(context).commonReason, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: adjustmentType,
              decoration: InputDecoration(labelText: appText(context).commonType),
              items: [
                for (final t in kStockAdjustmentTypes)
                  DropdownMenuItem(
                    value: t,
                    child: Text(t[0] + t.substring(1).toLowerCase()),
                  ),
              ],
              onChanged: onTypeChanged,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('update-stock-reason'),
              controller: reasonController,
              decoration: InputDecoration(
                labelText: appText(context).commonNoteOptional,
                hintText: appText(context).updateStockScreenEGSupplierDelivery123,
              ),
            ),
            const SizedBox(height: 16),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  error!,
                  key: const Key('update-stock-error'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('update-stock-save'),
                onPressed: saving ? null : onSubmit,
                child: saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(appText(context).commonSaveStockUpdate),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
