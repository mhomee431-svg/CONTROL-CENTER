import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/numeric_input.dart';
import '../../../products/domain/product_form_rules.dart';
import '../../../products/domain/product_models.dart';
import '../../../products/presentation/controllers/products_controller.dart';
import '../../../products/presentation/widgets/product_form_messages.dart';
import '../widgets/pricing_shared.dart';
import '../../../inventory/presentation/widgets/inventory_shared.dart'
    show moneyLabel, trimNumber, InfoChip;

/// Update Price — edit one product's selling price and MRP. The PATCH goes
/// through the products controller, which swaps in the server response, so
/// the list and every other screen stay consistent.
///
/// Opened with a product (from the price list) or with a product picker.
class UpdatePriceScreen extends ConsumerStatefulWidget {
  const UpdatePriceScreen({super.key, this.product});

  final ShopProductItem? product;

  @override
  ConsumerState<UpdatePriceScreen> createState() => _UpdatePriceScreenState();
}

class _UpdatePriceScreenState extends ConsumerState<UpdatePriceScreen> {
  ShopProductItem? _selected;
  late final TextEditingController _priceController;
  late final TextEditingController _mrpController;
  bool _saving = false;
  String? _error;

  /// True once the PATCH succeeded — drives the inline confirmation panel
  /// (`update-price-success`). Cleared as soon as the shopkeeper edits again.
  bool _saved = false;

  bool get _pickerMode => widget.product == null && _selected == null;

  @override
  void initState() {
    super.initState();
    _selected = widget.product;
    final initial = widget.product;
    _priceController = TextEditingController(
      text: initial == null ? '' : trimNumber(initial.price),
    );
    _mrpController = TextEditingController(
      text: initial?.mrp == null ? '' : trimNumber(initial!.mrp!),
    );
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
    _priceController.dispose();
    _mrpController.dispose();
    super.dispose();
  }

  ShopProductItem get _product => _selected ?? widget.product!;

  void _selectProduct(ShopProductItem item) {
    setState(() {
      _selected = item;
      _priceController.text = trimNumber(item.price);
      _mrpController.text = item.mrp == null ? '' : trimNumber(item.mrp!);
      _error = null;
      _saved = false;
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    // Validated through the SAME rules the create sheet uses, rather than a
    // private copy. They used to disagree: this screen rejected a price of 0
    // (`price <= 0`) while `ProductFormRules.price` — and the backend's `ge=0`
    // — allow it, so a product that could be CREATED at zero could never be
    // edited back to zero. Spec §36 says "Selling Price >= 0 / MRP >= 0" and
    // §132 lists "zero" as a case, so zero is legal here.
    final priceFailure = ProductFormRules.price(_priceController.text);
    if (priceFailure != null) {
      setState(() => _error = productFormErrorText(context, priceFailure));
      return;
    }
    final price = double.parse(_priceController.text.trim());

    final mrpRaw = _mrpController.text.trim();
    // MRP stays optional, and the cross-field rule ("MRP cannot undercut the
    // selling price") comes from the shared rule too, so both screens enforce
    // one definition of an invalid relationship (§36).
    final mrpFailure = ProductFormRules.mrp(
      mrpRaw,
      priceText: _priceController.text,
    );
    if (mrpFailure != null) {
      setState(() => _error = productFormErrorText(context, mrpFailure));
      return;
    }
    final mrp = mrpRaw.isEmpty ? null : double.parse(mrpRaw);

    setState(() {
      _saving = true;
      _error = null;
      _saved = false;
    });
    final ok = await ref
        .read(productsControllerProvider.notifier)
        .saveEdits(productId: _product.id, price: price, mrp: mrp);
    if (!mounted) return;
    if (ok) {
      // Confirmation stays ON the screen (an inline panel rather than a
      // SnackBar + pop) so the shopkeeper sees the server-accepted price and
      // can keep editing without losing context.
      setState(() {
        _saving = false;
        _saved = true;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(appText(context).commonPriceUpdated)));
    } else {
      final message = ref.read(productsControllerProvider).message;
      setState(() {
        _saving = false;
        _error = message ?? 'Could not update the price. Retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(productsControllerProvider);

    if (_pickerMode) {
      return Scaffold(
        appBar: AppBar(title: Text(appText(context).commonUpdatePrice)),
        body: PricingAsyncBody(
          status: state.status,
          message: state.message,
          onRetry: () => ref.read(productsControllerProvider.notifier).load(),
          builder: (context) => PricingProductPicker(
            items: state.items,
            onSelected: _selectProduct,
          ),
        ),
      );
    }

    final product = _product;
    final discount = discountPercentOff(product.mrp, product.price);

    return Scaffold(
      appBar: AppBar(
        title: Text(appText(context).commonUpdatePrice),
        actions: [
          if (widget.product == null)
            IconButton(
              tooltip: appText(context).commonChooseAnotherProduct4,
              icon: const Icon(Icons.swap_horiz_outlined),
              onPressed: () => setState(() => _selected = null),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    appText(context).updatePriceScreenCurrentValueValue2(moneyLabel(product.price), product.mrp == null ? '' : ' · MRP ${moneyLabel(product.mrp!)}'),
                    key: const Key('update-price-current'),
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (discount != null) ...[
                    const SizedBox(height: 6),
                    InfoChip(
                      label: '${trimNumber(discount)}% off',
                      color: AppTheme.verifiedGreen,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_saved) ...[
            const SizedBox(height: 16),
            Card(
              key: const Key('update-price-success'),
              margin: EdgeInsets.zero,
              color: AppTheme.verifiedGreen.withValues(alpha: 0.10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 20,
                      color: AppTheme.verifiedGreen,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        appText(context).updatePriceScreenPriceUpdatedNowValueValue2(_priceController.text.trim(), _mrpController.text.trim().isEmpty ? '' : ' · MRP ₹${_mrpController.text.trim()}'),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const Key('update-price-field'),
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    // Signed, matching the create sheet: the field can hold `-50`
                    // so the shared validator can EXPLAIN why it is rejected.
                    // Sign-free here silently swallowed the minus and saved +50,
                    // which is worse than being told the price is invalid.
                    inputFormatters: NumericInput.decimal(allowSign: true),
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: appText(context).updatePriceScreenSellingPrice,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('update-price-mrp-field'),
                    controller: _mrpController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: NumericInput.decimal(allowSign: true),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => FocusScope.of(context).unfocus(),
                    decoration: InputDecoration(
                      labelText: appText(context).updatePriceScreenMRPOptional,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        key: const Key('update-price-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('update-price-save'),
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(appText(context).commonSavePrice),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
