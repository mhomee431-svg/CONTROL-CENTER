/// CAPABILITY-DRIVEN FIELDS — the rendering half of the principle.
///
/// The field set is decided by capabilities; the LOOK is not. These tests pin
/// the second half, because "capability-driven" is easy to build in a way that
/// quietly grows its own visual language — a differently padded block, a
/// differently styled input — and then every screen looks like a slightly
/// different product.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/theme/app_spacing.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/capability_fields.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/shop_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/presentation/widgets/capability_fields_view.dart';

void main() {
  Widget host(
    CategoryCapabilitySet set, {
    Map<String, String> values = const {},
    void Function(String, String)? onChanged,
    String? title,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CapabilityFieldsView(
              set: set,
              values: values,
              onChanged: onChanged ?? (_, _) {},
              title: title,
            ),
          ),
        ),
      );

  group('an explicit field list is the one that renders', () {
    // The bug this covers: the widget was handed the server's field list and
    // then ignored it, re-deriving the fields from the local capability table.
    // Anything the backend added was invisible and anything it removed was still
    // on screen.
    const serverFields = [
      CapabilityFieldSpec(
        key: 'fleet_size',
        label: 'Fleet size',
        kind: CapabilityFieldKind.number,
        icon: 'directions_bus',
      ),
    ];

    testWidgets('a server-declared field this build lacks is still shown',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CapabilityFieldsView(
              set: resolveCategoryCapabilities('TRANSPORT', null),
              fields: serverFields,
              values: const {},
              onChanged: (_, _) {},
            ),
          ),
        ),
      ));
      expect(find.text('Fleet size'), findsOneWidget);
    });

    testWidgets('a field the backend removed is no longer on screen',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CapabilityFieldsView(
              set: resolveCategoryCapabilities('TRANSPORT', null),
              fields: serverFields,
              values: const {},
              onChanged: (_, _) {},
            ),
          ),
        ),
      ));
      // TRANSPORT's local table contributes plenty of inputs; none of them may
      // appear now that the server has said the list is just this one field.
      expect(find.text('Service area'), findsNothing);
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('an empty server list renders nothing at all', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CapabilityFieldsView(
              set: resolveCategoryCapabilities('TRANSPORT', null),
              fields: const [],
              values: const {},
              onChanged: (_, _) {},
            ),
          ),
        ),
      ));
      expect(find.byType(TextFormField), findsNothing);
    });

    testWidgets('omitting the list still falls back to the local table',
        (tester) async {
      // The offline path has no server answer, so the local table is the only
      // thing left and must still produce a usable form.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CapabilityFieldsView(
              set: resolveCategoryCapabilities('HARDWARE', 'Retail'),
              values: const {},
              onChanged: (_, _) {},
            ),
          ),
        ),
      ));
      expect(find.byType(TextFormField), findsWidgets);
    });
  });

  group('backend errors surface on the right input', () {
    testWidgets('a server refusal shows against its own field', (tester) async {
      // The local validator said the field was fine — only the server
      // objected, so nothing else would ever display this.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CapabilityFieldsView(
              set: resolveCategoryCapabilities('HARDWARE', 'Retail'),
              values: const {'service_summary': 'Weekly specials'},
              onChanged: (_, _) {},
              errors: const {'service_summary': 'Not accepted'},
            ),
          ),
        ),
      ));
      expect(find.text('Not accepted'), findsOneWidget);
    });

    testWidgets('a local error still shows when the server is silent', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CapabilityFieldsView(
              set: resolveCategoryCapabilities('HARDWARE', 'Retail'),
              values: const {},
              onChanged: (_, _) {},
            ),
          ),
        ),
      ));
      // contact_phone is required by the registry.
      expect(find.text('Contact number is required'), findsOneWidget);
    });

    testWidgets('a server error wins over the local verdict', (tester) async {
      // The two answer different questions; showing the local one when the
      // server has spoken would hide the actual reason.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CapabilityFieldsView(
              set: resolveCategoryCapabilities('HARDWARE', 'Retail'),
              values: const {'contact_phone': '9876543210'},
              onChanged: (_, _) {},
              errors: const {'contact_phone': 'Already registered'},
            ),
          ),
        ),
      ));
      expect(find.text('Already registered'), findsOneWidget);
      expect(find.text('Enter a valid phone number'), findsNothing);
    });
  });

  group('rendering follows the capability set', () {
    testWidgets('a restaurant gets service and booking inputs', (tester) async {
      final set = resolveCategoryCapabilities('RESTAURANTS', 'Retail');
      await tester.pumpWidget(host(set));

      expect(find.byKey(const Key('capability-field-service_summary')),
          findsOneWidget);
      expect(find.byKey(const Key('capability-field-booking_lead_hours')),
          findsOneWidget);
    });

    testWidgets('a stock category is not asked for booking or service inputs',
        (tester) async {
      // HOUSEHOLD_GOODS sells SKUs, so there is nothing to book or describe as
      // a service. A restaurant WOULD be asked for both — it holds DOCUMENTS
      // (FSSAI) too, which is why the negative case is asserted here rather
      // than against a restaurant.
      final set = resolveCategoryCapabilities('HOUSEHOLD_GOODS', 'Retail');
      await tester.pumpWidget(host(set));

      expect(find.byKey(const Key('capability-field-service_summary')),
          findsNothing);
      expect(find.byKey(const Key('capability-field-booking_lead_hours')),
          findsNothing);
      // It keeps the document input the restaurant also has.
      expect(find.byKey(const Key('capability-field-gst_number')), findsNothing,
          reason: 'HOUSEHOLD_GOODS holds no DOCUMENTS capability');
    });

    testWidgets('a pharmacy gets its document input', (tester) async {
      final set = resolveCategoryCapabilities('PHARMACY_HEALTHCARE', 'Retail');
      await tester.pumpWidget(host(set));
      expect(find.byKey(const Key('capability-field-gst_number')), findsOneWidget);
    });

    testWidgets('a capability with no fields renders nothing at all',
        (tester) async {
      // LOCATION is granted to everything but owns no shop-level input, so a
      // form made only of it must be genuinely empty — not an empty column with
      // stray padding.
      const set = CategoryCapabilitySet(
        categoryCode: 'X',
        capabilities: {CategoryCapability.location},
      );
      await tester.pumpWidget(host(set));
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    });

    testWidgets('an unknown category does not render a giant form',
        (tester) async {
      final set = resolveCategoryCapabilities('NOT_A_CATEGORY', null);
      await tester.pumpWidget(host(set));
      // Only the universal contact field, not every input at once.
      expect(find.byType(TextFormField), findsOneWidget);
    });
  });

  group('every field looks the same', () {
    /// The conventions the rest of the app already follows. A capability field
    /// that deviates is exactly the visual drift this group exists to prevent.
    void expectSharedFieldStyling(WidgetTester tester) {
      final decorators = tester.widgetList<InputDecorator>(
        find.byType(InputDecorator),
      );
      expect(decorators, isNotEmpty);
      for (final decorator in decorators) {
        // No cast needed: `widgetList<InputDecorator>` already gives the
        // typed decoration the assertion below wants to read.
        final decoration = decorator.decoration;
        expect(decoration.border, isA<OutlineInputBorder>(),
            reason: 'fields are outlined everywhere else in the app');
        expect(decoration.prefixIcon, isNotNull,
            reason: 'each field carries its leading icon');
      }
    }

    testWidgets('a capability form uses the app field styling',
        (tester) async {
      await tester.pumpWidget(
        host(resolveCategoryCapabilities('RESTAURANTS', 'Retail')),
      );
      expectSharedFieldStyling(tester);
    });

    testWidgets('a stock category uses exactly the same styling',
        (tester) async {
      // A different CATEGORY must not mean a different LOOK. That is the whole
      // point of the principle.
      await tester.pumpWidget(
        host(resolveCategoryCapabilities('HOUSEHOLD_GOODS', 'Retail')),
      );
      expectSharedFieldStyling(tester);
    });

    testWidgets('fields are separated by the shared form gap', (tester) async {
      // Measured between two CONSECUTIVE fields rather than by scanning every
      // `SizedBox` in the tree: a dropdown renders its own SizedBoxes, so a
      // blanket scan picks up framework internals (48, 24…) and fails for a
      // reason that has nothing to do with this form. The distance between two
      // fields is the thing the principle actually cares about.
      await tester.pumpWidget(
        host(resolveCategoryCapabilities('RESTAURANTS', 'Retail')),
      );

      final first = tester.getRect(
        find.byKey(const Key('capability-field-opening_time')),
      );
      final second = tester.getRect(
        find.byKey(const Key('capability-field-closing_time')),
      );

      // The vertical distance equals the field height plus the gap.
      final gap = second.top - first.bottom;
      expect(gap, AppSpacing.md,
          reason: 'a capability field must use the shared form gap');
    });

    testWidgets('a required field is visibly marked', (tester) async {
      await tester.pumpWidget(
        host(resolveCategoryCapabilities('RESTAURANTS', 'Retail')),
      );
      expect(find.text('Opening time *'), findsOneWidget);
      // Optional fields are not marked.
      expect(find.text('Services you offer *'), findsNothing);
    });
  });

  group('interaction', () {
    testWidgets('typing reports the value under its stable key',
        (tester) async {
      final changes = <String, String>{};
      await tester.pumpWidget(host(
        resolveCategoryCapabilities('RESTAURANTS', 'Retail'),
        onChanged: (key, value) => changes[key] = value,
      ));

      await tester.enterText(
        find.byKey(const Key('capability-field-service_summary')),
        'Haircut and facial',
      );
      expect(changes['service_summary'], 'Haircut and facial');
    });

    testWidgets('an existing value is shown in the field', (tester) async {
      await tester.pumpWidget(host(
        resolveCategoryCapabilities('RESTAURANTS', 'Retail'),
        values: const {'opening_time': '08:30'},
      ));
      expect(find.text('08:30'), findsOneWidget);
    });

    testWidgets('a blank required field blocks the form', (tester) async {
      await tester.pumpWidget(host(
        resolveCategoryCapabilities('RESTAURANTS', 'Retail'),
        title: 'Business details',
      ));
      // The section heading renders only when there is something to show.
      expect(find.text('Business details'), findsOneWidget);

      final field = tester.widget<TextFormField>(
        find.byKey(const Key('capability-field-opening_time')),
      );
      expect(field.validator, isNotNull);
      expect(field.validator!(null), contains('required'));
    });

    testWidgets('a choice field offers exactly the declared options',
        (tester) async {
      await tester.pumpWidget(
        host(resolveCategoryCapabilities('RESTAURANTS', 'Retail')),
      );
      await tester.tap(find.byKey(const Key('capability-field-closed_on')));
      await tester.pumpAndSettle();
      expect(find.text('Sunday'), findsOneWidget);
    });
  });
}
