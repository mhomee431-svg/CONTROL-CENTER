import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/ui/numeric_input.dart';
import '../../../offers/domain/offer_models.dart';
import '../../../offers/presentation/controllers/offers_controller.dart';
import '../../../products/domain/product_models.dart';
import '../../../products/presentation/controllers/products_controller.dart';

/// Create Offer — the full-screen offer builder: title, type, discount,
/// validity window and the shop products the offer applies to, submitted as
/// ONE atomic create+link call (`POST /shops/{id}/offers/assign`).
class CreateOfferScreen extends ConsumerStatefulWidget {
  const CreateOfferScreen({super.key});

  @override
  ConsumerState<CreateOfferScreen> createState() => _CreateOfferScreenState();
}

class _CreateOfferScreenState extends ConsumerState<CreateOfferScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _discountController = TextEditingController();
  final _termsController = TextEditingController();

  ShopkeeperOfferType _type = ShopkeeperOfferType.percentageDiscount;
  DateTime? _start;
  DateTime? _end;
  final Set<int> _selectedProductIds = {};
  String? _fieldError;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final state = ref.read(productsControllerProvider);
      if (state.status == ProductsStatus.loading && state.items.isEmpty) {
        ref.read(productsControllerProvider.notifier).load();
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _discountController.dispose();
    _termsController.dispose();
    super.dispose();
  }

  bool get _needsDiscount =>
      _type.requiresPercentage || _type.requiresFlatValue;

  String? _validate() {
    final titleError = OfferValidators.title(_titleController.text);
    if (titleError != null) return titleError;

    final discountError = OfferValidators.discount(
      _type,
      _discountController.text,
      _discountController.text,
    );
    if (discountError != null) return discountError;

    final periodError = OfferValidators.period(_start, _end);
    if (periodError != null) return periodError;

    if (_selectedProductIds.isEmpty) {
      return 'Select at least one product for the offer';
    }
    return null;
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _start : _end) ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final error = _validate();
    if (error != null) {
      setState(() => _fieldError = error);
      return;
    }
    setState(() => _fieldError = null);

    final discountRaw = double.tryParse(_discountController.text.trim());
    final ok = await ref
        .read(offersControllerProvider.notifier)
        .assign(
          OfferAssignRequest(
            title: _titleController.text.trim(),
            offerType: _type,
            startDate: _start!,
            endDate: _end!,
            shopProductIds: _selectedProductIds.toList(),
            discountValue: _type.requiresFlatValue ? discountRaw : null,
            discountPercentage: _type.requiresPercentage ? discountRaw : null,
            termsConditions: _termsController.text,
          ),
        );
    if (!mounted) return;
    if (ok) {
      ref.read(offersControllerProvider.notifier).reset();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: Key('create-offer-success'),
          content: Text('Offer created and linked to your products'),
        ),
      );
      // Best-effort hand-off to the offers list. The screen must also render
      // standalone (design previews / widget tests mount it without the app
      // router), so navigation happens only when a GoRouter is in scope.
      GoRouter.maybeOf(context)?.go(Routes.activeOffers);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsControllerProvider);
    final assign = ref.watch(offersControllerProvider);
    final saving = assign.status == OfferAssignStatus.saving;
    final assignError = assign.status == OfferAssignStatus.error
        ? assign.message
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Create offer')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                key: const Key('offer-title-field'),
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Offer title',
                  hintText: 'e.g. Monsoon Sale',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ShopkeeperOfferType>(
                key: const Key('offer-type-dropdown'),
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Offer type'),
                items: [
                  for (final t in ShopkeeperOfferType.values)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (v) => setState(() {
                  _type = v ?? ShopkeeperOfferType.percentageDiscount;
                  _discountController.clear();
                }),
              ),
              if (_needsDiscount) ...[
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('offer-discount-field'),
                  controller: _discountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: NumericInput.decimal(),
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: _type.requiresPercentage
                        ? 'Discount percentage (%)'
                        : 'Discount amount (₹)',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _DateField(
                      key: const Key('offer-start-date'),
                      label: 'Start date',
                      value: _start,
                      onTap: () => _pickDate(isStart: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DateField(
                      key: const Key('offer-end-date'),
                      label: 'End date',
                      value: _end,
                      onTap: () => _pickDate(isStart: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('offer-terms-field'),
                controller: _termsController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Terms & conditions (optional)',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Apply to products',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                _selectedProductIds.isEmpty
                    ? 'Nothing selected'
                    : '${_selectedProductIds.length} product(s) selected',
                key: const Key('offer-selection-count'),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              const SizedBox(height: 8),
              _ProductChecklist(
                status: products.status,
                message: products.message,
                items: products.items,
                selectedIds: _selectedProductIds,
                onRetry: () =>
                    ref.read(productsControllerProvider.notifier).load(),
                onToggle: (id) => setState(() {
                  if (!_selectedProductIds.add(id)) {
                    _selectedProductIds.remove(id);
                  }
                }),
              ),
              const SizedBox(height: 16),
              if (_fieldError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _fieldError!,
                    key: const Key('offer-field-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              if (assignError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    assignError,
                    key: const Key('offer-submit-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      // The primary action lives OUTSIDE the scroll view so it stays reachable
      // no matter how long the product catalogue grows.
      bottomNavigationBar: Material(
        elevation: 8,
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              key: const Key('offer-submit'),
              onPressed: saving ? null : _submit,
              child: saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create offer'),
            ),
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? 'Select date'
        : '${value!.day}/${value!.month}/${value!.year}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, isDense: true),
        child: Text(text, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}

/// Product multi-select for the offer — checkboxes over the shop catalog.
class _ProductChecklist extends StatelessWidget {
  const _ProductChecklist({
    required this.status,
    required this.message,
    required this.items,
    required this.selectedIds,
    required this.onRetry,
    required this.onToggle,
  });

  final ProductsStatus status;
  final String? message;
  final List<ShopProductItem> items;
  final Set<int> selectedIds;
  final VoidCallback onRetry;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      ProductsStatus.loading => const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      ),
      ProductsStatus.accessDenied || ProductsStatus.error => Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          message ?? 'Could not load products.',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ),
      ProductsStatus.ready => Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (final item in items)
              CheckboxListTile(
                key: Key('offer-product-${item.id}'),
                dense: true,
                value: selectedIds.contains(item.id),
                title: Text(item.name, style: const TextStyle(fontSize: 14)),
                subtitle: Text(
                  '₹${item.price}',
                  style: const TextStyle(fontSize: 12),
                ),
                onChanged: (_) => onToggle(item.id),
              ),
          ],
        ),
      ),
    };
  }
}
