import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_endpoints.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_providers.dart';
import 'package:hyperlocal_shopkeeper_app/core/theme/app_spacing.dart';
import 'package:hyperlocal_shopkeeper_app/core/ui/app_section_header.dart';
import 'package:hyperlocal_shopkeeper_app/core/ui/numeric_input.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/product_attributes.dart';

/// The category attributes for one merchant category, plus where they came from.
///
/// A null [attributes] means "the backend never answered": the form renders
/// without extra inputs rather than guessing them, because an invented key in the
/// payload is REFUSED — and a refused payload reads as a bug to the shopkeeper
/// who typed into it. An EMPTY list is meaningful: the category sells services
/// and has no product form, which renders as nothing rather than an error.
class ProductAttributesState {
  const ProductAttributesState({required this.attributes, required this.offline});

  const ProductAttributesState.empty()
      : attributes = const [],
        offline = false;

  final List<ProductAttributeSpec>? attributes;
  final bool offline;
}

/// Loads the product-attribute definitions for a merchant category.
///
/// There is deliberately NO local fallback table here, unlike the capability
/// fields: those have one because an offline registration form must stay
/// usable, whereas a product form already works without the extra inputs. The
/// only way to be sure the set matches what the backend will accept is to ask
/// the backend, so a failure renders nothing rather than a guess.
final productAttributesProvider =
    FutureProvider.family<ProductAttributesState, String>((ref, category) async {
  if (category.isEmpty) return const ProductAttributesState.empty();
  try {
    final data = await ref.watch(apiClientProvider).get(
          ApiEndpoints.businessCategoryProductAttributes(category),
        );
    if (data is! Map) {
      return const ProductAttributesState(attributes: null, offline: true);
    }
    final parsed = CategoryProductAttributes.fromJson(
      data as Map<String, dynamic>,
    );
    return ProductAttributesState(attributes: parsed.attributes, offline: false);
  } catch (_) {
    return const ProductAttributesState(attributes: null, offline: true);
  }
});

/// One input per declared attribute, in the backend's order and wording.
///
/// Only the EXTRA fields render here. The main form already carries the
/// column-routed keys (name, price, barcode …) and the taxonomy pickers carry the
/// catalog ids, so rendering them again would be two boxes for one value. Each
/// visible spec's own `errorFor` is what validates on submit — nothing the server
/// declared required can slip past by being absent from the form.
class ProductAttributesSection extends StatelessWidget {
  const ProductAttributesSection({
    super.key,
    required this.specs,
    required this.values,
    required this.onChanged,
    this.enabled = true,
    this.errors = const <String, String>{},
  });

  /// The declared EXTRA fields only. `toAttributeMap` decides the submitted set,
  /// so the rendered inputs and the payload cannot disagree about which keys
  /// travel.
  final List<ProductAttributeSpec> specs;

  /// Current values, keyed by spec key.
  final Map<String, String> values;

  /// Called with `(key, value)` on every edit.
  final void Function(String key, String value) onChanged;

  final bool enabled;
  final Map<String, String> errors;

  @override
  Widget build(BuildContext context) {
    if (specs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(
          title: 'Trade details',
          padding: EdgeInsets.only(bottom: 10, top: 4),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < specs.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md),
          _input(context, specs[i]),
        ],
      ],
    );
  }

  Widget _input(BuildContext context, ProductAttributeSpec spec) {
    final value = values[spec.key] ?? '';
    final decoration = InputDecoration(
      labelText: spec.required ? '${spec.label} *' : spec.label,
      hintText: spec.hint,
      border: const OutlineInputBorder(),
      errorText: errors[spec.key],
    );
    final key = Key('product-attribute-${spec.key}');
    switch (spec.kind) {
      case ProductAttributeKind.choice:
        return DropdownButtonFormField<String>(
          key: key,
          initialValue: spec.options.contains(value) ? value : null,
          items: [
            for (final option in spec.options)
              DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: enabled ? (next) => onChanged(spec.key, next ?? '') : null,
          decoration: decoration,
          validator: (next) => errors[spec.key] ?? spec.errorFor(next),
        );
      case ProductAttributeKind.multiline:
        return TextFormField(
          key: key,
          initialValue: value,
          enabled: enabled,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (next) => onChanged(spec.key, next),
          decoration: decoration,
          validator: (next) => errors[spec.key] ?? spec.errorFor(next),
        );
      case ProductAttributeKind.number:
        return TextFormField(
          key: key,
          initialValue: value,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: NumericInput.decimal(),
          onChanged: (next) => onChanged(spec.key, next),
          decoration: decoration,
          validator: (next) => errors[spec.key] ?? spec.errorFor(next),
        );
      case ProductAttributeKind.text:
        return TextFormField(
          key: key,
          initialValue: value,
          enabled: enabled,
          textCapitalization: TextCapitalization.words,
          onChanged: (next) => onChanged(spec.key, next),
          decoration: decoration,
          validator: (next) => errors[spec.key] ?? spec.errorFor(next),
        );
    }
  }
}
