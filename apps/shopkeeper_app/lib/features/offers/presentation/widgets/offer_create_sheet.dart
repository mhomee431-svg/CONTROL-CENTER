import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/utils/datetime_utils.dart';
import '../../../products/domain/product_models.dart';
import '../../../../core/ui/numeric_input.dart';
import '../../../products/presentation/controllers/products_controller.dart';
import '../../domain/offer_models.dart';
import '../controllers/offers_controller.dart';

/// Create-offer sheet: pick products from the loaded inventory, set the
/// offer type + discount + period, and submit atomically to the backend.
///
/// Client-side validation mirrors `ShopkeeperOfferAssign` rules; the
/// backend re-validates everything (plan limits, ownership, dates).
class OfferCreateSheet extends ConsumerStatefulWidget {
  const OfferCreateSheet({super.key});

  @override
  ConsumerState<OfferCreateSheet> createState() => _OfferCreateSheetState();
}

class _OfferCreateSheetState extends ConsumerState<OfferCreateSheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _percentage = TextEditingController();
  final _flatValue = TextEditingController();
  final _promoPrice = TextEditingController();
  final _terms = TextEditingController();

  ShopkeeperOfferType _type = ShopkeeperOfferType.percentageDiscount;

  /// When true the offer is created as a DRAFT: the backend stores it but
  /// customers never see it until the shopkeeper activates it.
  bool _saveAsDraft = false;
  DateTime? _start;
  DateTime? _end;
  final Set<int> _selectedIds = {};

  bool get _saving =>
      ref.watch(offersControllerProvider.select((s) => s.status)) ==
      OfferAssignStatus.saving;

  @override
  void dispose() {
    _title.dispose();
    _percentage.dispose();
    _flatValue.dispose();
    _promoPrice.dispose();
    _terms.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart
          ? (_start ?? now)
          : (_end ?? now.add(const Duration(days: 7))),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
      helpText: isStart ? 'Offer start date' : 'Offer end date',
    );
    if (picked == null || !mounted) return;
    setState(() => isStart ? _start = picked : _end = picked);
  }

  /// The exact offer this form is about to create.
  ///
  /// Built once and shown to the shopkeeper BEFORE it is sent: "Create offer"
  /// on a form with a percentage, a window and fifteen selected products is a
  /// lot to send on faith. The review step is what makes the tap reviewable.
  OfferAssignRequest get reviewDraft => OfferAssignRequest(
        title: _title.text.trim(),
        offerType: _type,
        discountPercentage: _type.requiresPercentage
            ? double.tryParse(_percentage.text.trim())
            : null,
        discountValue: _type.requiresFlatValue
            ? double.tryParse(_flatValue.text.trim())
            : null,
        promotionalPrice: _type.requiresPromotionalPrice
            ? double.tryParse(_promoPrice.text.trim())
            : null,
        startDate: _start!,
        endDate: _end!,
        status: _saveAsDraft ? 'DRAFT' : null,
        shopProductIds: _selectedIds.toList(growable: false),
        termsConditions: _terms.text.trim(),
      );

  Future<void> _submit() async {
    if (_saving) return; // double-submit guard
    if (!_formKey.currentState!.validate()) return;
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(appText(context).offerCreateSheetSelectAtLeastOneProduct),
        ),
      );
      return;
    }
    final periodError = OfferValidators.period(_start, _end);
    if (periodError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(periodError)));
      return;
    }

    // Review before sending. Cancelling the review leaves the form exactly as it
    // was - nothing is cleared and nothing leaves the device - so a shopkeeper
    // who misreads the summary can go back and fix it.
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => OfferReviewSheet(
        request: reviewDraft,
        productNames: {
          for (final item in ref.read(productsControllerProvider).items)
            item.id: item.name,
        },
        activatesImmediately: !_saveAsDraft,
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await ref
        .read(offersControllerProvider.notifier)
        .assign(reviewDraft);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
      final result = ref.read(offersControllerProvider).result;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            appText(context).offerCreateSheetOfferCreatedForLengthProduct(result?.productCount ?? _selectedIds.length),
          ),
        ),
      );
    } else {
      final message =
          ref.read(offersControllerProvider).message ??
          'Could not create the offer';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(
      productsControllerProvider.select((s) => s.items),
    );
    final theme = Theme.of(context);

    // SingleChildScrollView (not Padding) so the form stays reachable on short
    // screens and when the keyboard is open — the sheet content is taller than
    // a small viewport once every optional field is showing.
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    appText(context).commonCreateOffer2,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  // Accessible name for the icon-only dismiss control.
                  tooltip: appText(context).commonClose2,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 255,
              decoration: InputDecoration(
                labelText: appText(context).offerCreateSheetOfferTitle,
                hintText: appText(context).offerCreateSheetEGDiwali10Off,
                counterText: '',
              ),
              validator: OfferValidators.title,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ShopkeeperOfferType>(
              initialValue: _type,
              decoration: InputDecoration(labelText: appText(context).offerCreateSheetOfferType),
              items: [
                for (final t in ShopkeeperOfferType.values)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 12),
            if (_type.requiresPercentage)
              TextFormField(
                controller: _percentage,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: NumericInput.decimal(),
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: appText(context).offerCreateSheetDiscount,
                  suffixText: '%',
                ),
                validator: (v) =>
                    OfferValidators.discount(_type, v, _flatValue.text),
              )
            else if (_type.requiresFlatValue)
              TextFormField(
                controller: _flatValue,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: NumericInput.decimal(),
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: appText(context).offerCreateSheetDiscount2,
                  prefixText: '₹ ',
                ),
                validator: (v) =>
                    OfferValidators.discount(_type, _percentage.text, v),
              )
            else if (_type.requiresPromotionalPrice)
              TextFormField(
                controller: _promoPrice,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: NumericInput.decimal(),
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: appText(context).offerCreateSheetPromotionalPrice,
                  prefixText: '₹ ',
                  helperText: appText(context).offerCreateSheetFixedSalePriceCustomersPay,
                ),
                validator: (v) => OfferValidators.discount(
                    _type, _percentage.text, _flatValue.text, v),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: appText(context).offerCreateSheetStartDate,
                    value: _start,
                    onTap: () => _pickDate(isStart: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateField(
                    label: appText(context).offerCreateSheetEndDate,
                    value: _end,
                    onTap: () => _pickDate(isStart: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              key: const Key('offer-save-as-draft'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _saveAsDraft,
              onChanged: (v) => setState(() => _saveAsDraft = v),
              title: Text(appText(context).commonSaveAsDraft),
              subtitle: Text(
                  appText(context).offerCreateSheetKeptOffCustomerListingsUntil),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _terms,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 300,
              minLines: 1,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: appText(context).offerCreateSheetTermsConditionsOptional,
                hintText: appText(context).offerCreateSheetEGValidOnIn,
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              appText(context).offerCreateSheetAppliesToLengthSelected(_selectedIds.length),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            if (products.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  appText(context).offerCreateSheetNoProductsInInventoryYet,
                  style: TextStyle(color: theme.colorScheme.outline),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: products.length,
                  itemBuilder: (context, index) => _ProductCheckTile(
                    item: products[index],
                    selected: _selectedIds.contains(products[index].id),
                    onToggle: (id) => setState(() {
                      _selectedIds.contains(id)
                          ? _selectedIds.remove(id)
                          : _selectedIds.add(id);
                    }),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: (_saving || products.isEmpty) ? null : _submit,
              icon: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.local_offer_outlined),
              label: Text(appText(context).commonCreateOffer2),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, this.onTap});

  final String label;
  final DateTime? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? 'Select'
        : '${value!.day}/${value!.month}/${value!.year}';
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        alignment: Alignment.centerLeft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 2),
          Text(text, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}

class _ProductCheckTile extends StatelessWidget {
  const _ProductCheckTile({
    required this.item,
    required this.selected,
    required this.onToggle,
  });

  final ShopProductItem item;
  final bool selected;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      value: selected,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        appText(context).offerCreateSheetValueQtyQuantity(item.price.toStringAsFixed(0), item.quantity),
        style: const TextStyle(fontSize: 12),
      ),
      onChanged: (_) => onToggle(item.id),
    );
  }
}


/// The review step of creating an offer: Preview -> Confirm.
///
/// Creating an offer is a one-way, many-field action — a percentage, a date
/// window and a list of products, all sent in one tap. The shopkeeper has no
/// second chance to notice the wrong column, so this shows the draft in plain
/// words BEFORE anything is sent, and Cancel returns to the form with the draft
/// untouched.
///
/// It sends nothing itself. The create sheet re-sends the SAME [request] it
/// previewed, so what was reviewed and what is created cannot differ.
class OfferReviewSheet extends StatelessWidget {
  const OfferReviewSheet({
    required this.request,
    required this.productNames,
    required this.activatesImmediately,
    super.key,
  });

  final OfferAssignRequest request;

  /// Shop-product id -> name, so the summary speaks the shopkeeper's language
  /// instead of showing a list of ids.
  final Map<int, String> productNames;

  /// False for a draft, which is stored but never shown to customers.
  final bool activatesImmediately;

  /// The one sentence that says what will happen to CUSTOMERS, which is the
  /// question a shopkeeper actually has when saving an offer.
  String get _visibilityLine => activatesImmediately
      ? 'Goes live for customers now'
      : 'Saved as draft — customers will not see it';

  /// What the offer does, in one line.
  String get _valueLine {
    switch (request.offerType) {
      case ShopkeeperOfferType.percentageDiscount:
        final pct = request.discountPercentage;
        return pct == null ? request.offerType.label : '${_oneDecimal(pct)}% off';
      case ShopkeeperOfferType.flatDiscount:
        final v = request.discountValue;
        return v == null ? request.offerType.label : '?${_money(v)} off';
      case ShopkeeperOfferType.promotionalPrice:
        final v = request.promotionalPrice;
        return v == null ? request.offerType.label : 'Price ?${_money(v)}';
      case ShopkeeperOfferType.buyXGetY:
      case ShopkeeperOfferType.bundle:
      case ShopkeeperOfferType.freeShipping:
        return request.offerType.label;
    }
  }

  /// One decimal place, ALWAYS.
  ///
  /// "10% off" and "10.0% off" are the same offer, but a preview whose shape
  /// changes with the typed value ("10% off" then "12.5% off") reads like two
  /// different things and makes the shopkeeper re-check the number.
  static String _oneDecimal(double v) => v.toStringAsFixed(1);

  static String _money(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  String get _windowLine =>
      '${DateTimeUtils.formatShortDate(request.startDate)} — '
      '${DateTimeUtils.formatShortDate(request.endDate)}';

  String get _productsLine {
    final names = request.shopProductIds
        .map((id) => productNames[id])
        .whereType<String>()
        .toList(growable: false);
    if (names.isEmpty) return '';
    if (names.length == 1) return 'Applies to: ${names.first}';
    return 'Applies to: ${names.length} products';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Review offer',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              request.title,
              key: const Key('offer-review-title'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(_valueLine, style: theme.textTheme.bodyMedium),
            Text(_windowLine, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text(
              _visibilityLine,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_productsLine.isNotEmpty)
              Text(_productsLine, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('offer-review-cancel'),
                    // false, not null: the caller checks `== true`, so a plain
                    // "not confirmed" is unambiguous.
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(appText(context).commonEdit),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const Key('offer-review-confirm'),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(
                      activatesImmediately
                          ? appText(context).commonCreateOffer2
                          : appText(context).commonSaveAsDraft,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
