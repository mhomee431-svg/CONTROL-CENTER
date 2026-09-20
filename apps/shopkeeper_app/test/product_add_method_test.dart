import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/pos/data/pos_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/widgets/product_sheets.dart';

import 'fakes.dart';

/// The Add-Product method chooser: Manual, Barcode, Bulk Excel, and the POS
/// entry that only lights up once the backend actually offers POS.
///
/// The spec is "POS where enabled" — so the POS tile must be driven by the real
/// connector catalogue, never by a hard-coded label. Only the POS repository is
/// faked; the controller and the sheet run for real.
ProviderContainer makeContainer(FakePosRepo repo) {
  return ProviderContainer(
    overrides: [
      posRepositoryProvider.overrideWithValue(repo),
      tokenStoreProvider.overrideWithValue(
        InMemoryTokenStore(accessToken: 'test-access-token'),
      ),
      selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
    ],
  );
}

Future<void> pumpSheet(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: ProductAddMethodSheet()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The state of the POS entry — its enablement is the whole contract.
ListTile posTile(WidgetTester tester) =>
    tester.widget<ListTile>(find.byKey(const Key('add-product-pos')));

void main() {
  group('ProductAddMethodSheet', () {
    testWidgets('always offers the three primary methods', (tester) async {
      final repo = FakePosRepo(providers: const []);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      await pumpSheet(tester, container);

      expect(find.text('Enter manually'), findsOneWidget);
      expect(find.text('Scan barcode'), findsOneWidget);
      expect(find.text('Bulk Excel import'), findsOneWidget);
    });

    testWidgets('POS stays disabled when the backend offers no provider',
        (tester) async {
      final repo = FakePosRepo(providers: const []);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      await pumpSheet(tester, container);

      final tile = posTile(tester);
      expect(tile.enabled, isFalse);
      expect(tile.onTap, isNull);
      expect(find.text('Available after POS integration'), findsOneWidget);
    });

    testWidgets('POS becomes actionable once a provider is published',
        (tester) async {
      final repo = FakePosRepo();
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      await pumpSheet(tester, container);

      // The chooser resolved the catalogue itself rather than trusting a flag.
      expect(repo.providerCalls, 1);
      final tile = posTile(tester);
      expect(tile.enabled, isTrue);
      expect(tile.onTap, isNotNull);
      expect(find.text('Import products from your connected POS'), findsOneWidget);
      expect(find.text('Available after POS integration'), findsNothing);
    });

    testWidgets('an already-linked connector alone enables POS', (tester) async {
      // With a connector present the controller reports the integration and
      // NO providers — the entry must still be usable.
      final repo = FakePosRepo(
        integrations: [posIntegration()],
        providers: const [],
      );
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      await pumpSheet(tester, container);

      final tile = posTile(tester);
      expect(tile.enabled, isTrue);
      expect(tile.onTap, isNotNull);
    });
  });
}
