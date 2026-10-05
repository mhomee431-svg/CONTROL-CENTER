import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal_app/features/product_details/presentation/providers/product_details_providers.dart';
import 'package:hyperlocal_app/features/product_details/presentation/widgets/shop_inventory_section.dart';

/// Reads the live radius out of the controller, so a test can assert the STATE
/// and not only the label. Asserting only the label would still pass if the
/// label had been cached from the wrong step.
double? currentRadius(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ShopInventorySection)),
  );
  return container.read(productSearchRadiusProvider);
}

const Widget _emptySection = SizedBox(
  height: 900,
  child: ShopInventorySection(productId: 'p1', offers: []),
);

GoRouter _router({bool unverified = false}) => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => Scaffold(
        // Bounded: the empty state owns a scroll view, which needs a finite
        // height or the test renders itself with an infinite viewport.
        body: unverified
            ? const SizedBox(
                height: 900,
                child: ShopInventorySection(
                  productId: 'p1',
                  offers: [],
                  unverified: true,
                ),
              )
            : _emptySection,
      ),
    ),
    GoRoute(
      path: '/select-location',
      builder: (_, _) =>
          const Scaffold(body: Center(child: Text('SelectLocationPage'))),
    ),
    GoRoute(
      path: '/search-results-by-pin/:pin',
      builder: (_, state) => Scaffold(
        body: Center(child: Text('Pin:${state.pathParameters['pin']}')),
      ),
    ),
  ],
);

Future<void> _pump(WidgetTester tester, {bool unverified = false}) async {
  tester.view.physicalSize = const Size(400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(routerConfig: _router(unverified: unverified)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a live but empty inventory offers the three recoveries', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('No nearby shops found'), findsOneWidget);
    expect(find.byKey(const Key('inventorySearchWider')), findsOneWidget);
    expect(find.byKey(const Key('inventoryChangeLocation')), findsOneWidget);
    expect(find.byKey(const Key('inventorySearchAnotherArea')), findsOneWidget);
    // The first request is the BACKEND default; the label names what the NEXT
    // one will be, not what the current one is.
    expect(find.text('Search within 25 km'), findsOneWidget);
    expect(currentRadius(tester), isNull);
  });

  testWidgets('widen steps 25 -> 50 -> 100 and then stops', (tester) async {
    await _pump(tester);

    // The first load used the backend default (10 km), so the ladder the
    // customer walks is 25 → 50 → 100. Stepping to 10 would re-issue the very
    // query that just came back empty.
    for (final expected in [25.0, 50.0, 100.0]) {
      await tester.tap(find.byKey(const Key('inventorySearchWider')));
      await tester.pumpAndSettle();
      expect(
        currentRadius(tester),
        expected,
        reason: 'the provider must actually hold the widened radius',
      );
    }

    // 100 is the server's `le=100`; asking beyond it is a 422, so the control
    // disappears rather than inviting a request that cannot succeed.
    expect(find.byKey(const Key('inventorySearchWider')), findsNothing);
  });

  testWidgets('widen repaints its own label', (tester) async {
    await _pump(tester);
    expect(find.text('Search within 25 km'), findsOneWidget);

    await tester.tap(find.byKey(const Key('inventorySearchWider')));
    await tester.pumpAndSettle();

    expect(find.text('Search within 50 km'), findsOneWidget);
  });

  testWidgets('change location opens the picker', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('inventoryChangeLocation')));
    await tester.pumpAndSettle();

    expect(find.text('SelectLocationPage'), findsOneWidget);
  });

  testWidgets('search another area validates the pin before leaving', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('inventorySearchAnotherArea')));
    await tester.pumpAndSettle();
    expect(find.text('Enter Area Pin Code'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '12ab');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('areaPinCheck')));
    await tester.pumpAndSettle();
    expect(find.text('Enter Area Pin Code'), findsOneWidget);
    expect(find.text('Pin:12ab'), findsNothing);

    await tester.enterText(find.byType(TextField), '560001');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('areaPinCheck')));
    await tester.pumpAndSettle();

    expect(find.text('Pin:560001'), findsOneWidget);
  });

  testWidgets('an unverified (cached) empty state offers Retry, not widen', (
    tester,
  ) async {
    await _pump(tester, unverified: true);

    // A different fact needs a different recovery: we have not checked, so
    // re-asking is meaningful. Widening a question nobody answered is not.
    expect(find.text('Availability unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byKey(const Key('inventorySearchWider')), findsNothing);
    expect(find.byKey(const Key('inventoryChangeLocation')), findsNothing);
    expect(find.byKey(const Key('inventorySearchAnotherArea')), findsNothing);
  });
}
