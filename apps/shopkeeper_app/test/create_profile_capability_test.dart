import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/screens/create_profile_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/data/capability_fields_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/capability_fields.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/presentation/controllers/capability_fields_controller.dart';

import 'package:hyperlocal_shopkeeper_app/features/shops/domain/shop_models.dart';

import 'fakes.dart';

/// The capability-driven fields must appear in a REAL screen, not only in the
/// shared widget's own tests. Without this the view could sit unused and every
/// domain test would still pass — which is exactly the gap this covers.
Widget host(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: CreateProfileScreen()),
    );

ProviderContainer makeContainer(CapabilityFieldsState state) =>
    ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        // Override the loader, not the HTTP client: this test is about the
        // SCREEN's four states, and driving a real socket through them would
        // test Dio instead.
        capabilityFieldsProvider.overrideWith(
          (ref, arg) async => arg.category.isEmpty
              ? CapabilityFieldsState.empty
              : state,
        ),
      ],
    );

/// Picks a business category from the form's dropdown.
///
/// The section stays closed until a trade is chosen — that is the point of the
/// feature — so every rendering test has to make the same choice a shopkeeper
/// would before it can assert anything.
Future<void> chooseCategory(WidgetTester tester, String label) async {
  final dropdown = find.byType(DropdownButtonFormField<String>).first;
  // The dropdown sits well down a scrolling form, so it can start outside the
  // default 800x600 test surface and refuse the tap.
  await tester.ensureVisible(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// A tall surface so the whole one-page form is reachable without scrolling.
/// Scrolling into view is done explicitly where it matters instead.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('CreateProfileScreen capability fields', () {
    testWidgets('no fields render before a category is chosen', (tester) async {
      final container = makeContainer(
        const CapabilityFieldsState(
          fields: <CapabilityFieldSpec>[],
          source: CapabilityFieldsSource.server,
        ),
      );
      useTallSurface(tester);
      await tester.pumpWidget(host(container));
      await tester.pump();

      // The form is open, but it has not asked for anything yet.
      expect(find.text('Business details'), findsNothing);
    });

    testWidgets('choosing a category asks the backend for its fields',
        (tester) async {
      final container = makeContainer(
        CapabilityFieldsState(
          fields: capabilityFieldsFor(
            resolveCategoryCapabilities('RESTAURANTS', 'Retail'),
          ),
          source: CapabilityFieldsSource.server,
        ),
      );
      useTallSurface(tester);
      await tester.pumpWidget(host(container));
      await tester.pump();

      await chooseCategory(tester, 'Restaurants');

      // A restaurant is told about offerings; a hardware shop would not be.
      expect(find.text('Offerings'), findsOneWidget);
      expect(find.text('Service area'), findsNothing);
    });

    testWidgets('the offline notice appears when the server was unreachable',
        (tester) async {
      // The real case: fields from the built-in table, but the server never
      // answered. With no fields at all there is nothing to warn about, so the
      // notice would be noise.
      final container = makeContainer(
        CapabilityFieldsState(
          fields: capabilityFieldsFor(
            resolveCategoryCapabilities('HARDWARE', 'Retail'),
          ),
          source: CapabilityFieldsSource.offlineFallback,
        ),
      );
      useTallSurface(tester);
      await tester.pumpWidget(host(container));
      await tester.pump();
      await chooseCategory(tester, 'Hardware');

      expect(
        find.textContaining('Showing the last known fields'),
        findsOneWidget,
      );
      // The fields themselves still render — the fallback is not an error page.
      expect(find.text('Services you offer'), findsWidgets);
    });

    testWidgets('an offline save is disclosed, never implied to have worked',
        (tester) async {
      // The notice must exist precisely so a shopkeeper who typed a service
      // area is not left believing the server stored it.
      final container = makeContainer(
        CapabilityFieldsState(
          fields: capabilityFieldsFor(
            resolveCategoryCapabilities('PERSONAL_TRANSPORT_TRAVEL', 'Retail'),
          ),
          source: CapabilityFieldsSource.offlineFallback,
        ),
      );
      useTallSurface(tester);
      await tester.pumpWidget(host(container));
      await tester.pump();
      await chooseCategory(tester, 'Personal Transport / Personal Travel');

      expect(find.text('Service area'), findsWidgets);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
