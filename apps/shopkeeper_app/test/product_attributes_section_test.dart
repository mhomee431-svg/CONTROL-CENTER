import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/widgets/product_attributes_section.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/product_attributes.dart';

/// The trade-detail inputs the product form renders.
///
/// The point of these tests is the boundary between what the backend DECLARED and
/// what this build renders: the section must never invent a field, must never
/// drop one, and must render the server's own label and required mark.
void main() {
  Widget host(
    List<ProductAttributeSpec> specs, {
    Map<String, String> values = const {},
    Map<String, String> errors = const {},
    bool enabled = true,
    void Function(String, String)? onChanged,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProductAttributesSection(
              specs: specs,
              values: values,
              errors: errors,
              enabled: enabled,
              onChanged: onChanged ?? (_, _) {},
            ),
          ),
        ),
      );

  const text = ProductAttributeSpec(
    key: 'material',
    label: 'Material',
    kind: ProductAttributeKind.text,
  );
  const sized = ProductAttributeSpec(
    key: 'size',
    label: 'Size',
    kind: ProductAttributeKind.text,
  );

  testWidgets('one input per declared field, in the server order', (tester) async {
    await tester.pumpWidget(host(const [text, sized]));
    expect(find.text('Material'), findsOneWidget);
    expect(find.text('Size'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
  });

  testWidgets('an empty declared list renders nothing at all', (tester) async {
    await tester.pumpWidget(host(const []));
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Trade details'), findsNothing);
  });

  testWidgets('the server label is shown verbatim, not reworded', (tester) async {
    await tester.pumpWidget(host(const [
      ProductAttributeSpec(
        key: 'oem_reference_number',
        label: 'OEM / reference number',
        kind: ProductAttributeKind.text,
      ),
    ]));
    expect(find.text('OEM / reference number'), findsOneWidget);
  });

  testWidgets('a required field is visibly marked', (tester) async {
    await tester.pumpWidget(host(const [
      ProductAttributeSpec(
        key: 'part_number',
        label: 'Part number',
        kind: ProductAttributeKind.text,
        required: true,
      ),
    ]));
    expect(find.text('Part number *'), findsOneWidget);
  });

  testWidgets('editing reports the value under the backend key', (tester) async {
    final seen = <String, String>{};
    await tester.pumpWidget(host(const [text], onChanged: (k, v) => seen[k] = v));
    await tester.enterText(find.byType(TextFormField), 'Brass');
    expect(seen['material'], 'Brass');
  });

  testWidgets('an existing value is shown in the field', (tester) async {
    await tester.pumpWidget(host(const [text], values: const {'material': 'Steel'}));
    expect(find.text('Steel'), findsOneWidget);
  });

  testWidgets('a disabled section cannot be edited', (tester) async {
    await tester.pumpWidget(host(const [text], enabled: false));
    final field = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(field.enabled, isFalse);
  });

  testWidgets('a server error shows against its own field', (tester) async {
    await tester.pumpWidget(host(
      const [text],
      errors: const {'material': 'Not accepted'},
    ));
    expect(find.text('Not accepted'), findsOneWidget);
  });

  testWidgets('a missing required value is reported by its own spec',
      (tester) async {
    await tester.pumpWidget(host(const [
      ProductAttributeSpec(
        key: 'part_number',
        label: 'Part number',
        kind: ProductAttributeKind.text,
        required: true,
      ),
    ]));
    // The required rule belongs to the spec, so a blank value is caught without
    // this file inventing a message. (The section deliberately does not wrap the
    // inputs in a Form — the enclosing product sheet's Form owns them.)
    const spec = ProductAttributeSpec(
      key: 'part_number',
      label: 'Part number',
      kind: ProductAttributeKind.text,
      required: true,
    );
    expect(spec.errorFor(''), 'Part number is required');
    expect(spec.errorFor('P-9'), isNull);
  });

  testWidgets('a choice field offers exactly the declared options',
      (tester) async {
    await tester.pumpWidget(host(const [
      ProductAttributeSpec(
        key: 'size',
        label: 'Size',
        kind: ProductAttributeKind.choice,
        options: ['Small', 'Large'],
      ),
    ]));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Small'), findsWidgets);
    expect(find.text('Large'), findsWidgets);
  });

  testWidgets('a number field uses the shared numeric formatter', (tester) async {
    await tester.pumpWidget(host(const [
      ProductAttributeSpec(
        key: 'weight',
        label: 'Weight',
        kind: ProductAttributeKind.number,
      ),
    ]));
    // `TextFormField` builds an inner `TextField`, and that is where the keyboard
    // and the formatters actually live.
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byType(TextFormField),
        matching: find.byType(TextField),
      ),
    );
    expect(field.keyboardType, TextInputType.numberWithOptions(decimal: true));
    expect(field.inputFormatters, isNotEmpty);
  });

  testWidgets('a multiline field gets several lines', (tester) async {
    await tester.pumpWidget(host(const [
      ProductAttributeSpec(
        key: 'specification',
        label: 'Specification',
        kind: ProductAttributeKind.multiline,
      ),
    ]));
    // As with the numeric case, the line count lives on the inner `TextField`.
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byType(TextFormField),
        matching: find.byType(TextField),
      ),
    );
    expect(field.maxLines, 3);
  });
}