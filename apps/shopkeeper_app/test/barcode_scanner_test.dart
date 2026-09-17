import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/barcode/data/barcode_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/barcode/domain/barcode_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/barcode/presentation/widgets/barcode_sheets.dart';

import 'fakes.dart';

/// Scanner-sheet states: manual entry, product-not-found and the barcode
/// conflict escape. The camera itself (mobile_scanner) needs a platform view,
/// so the sheet contracts are covered here and the resolution / scan state
/// machine in `barcode_features_test.dart`.
void main() {
  /// Pumps a host screen whose button opens [sheet] over the barcode
  /// providers, then opens it.
  Future<void> openSheet(
    WidgetTester tester, {
    required Widget sheet,
    FakeBarcodeRepo? repo,
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        barcodeRepositoryProvider.overrideWithValue(repo ?? FakeBarcodeRepo()),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider
            .overrideWith(() => SelectedShopOverride(ownerShop(id: 10))),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => sheet,
                ),
                child: const Text('open scanner sheet'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open scanner sheet'));
    await tester.pumpAndSettle();
  }

  CatalogProductMatch catalogMatch({
    String name = 'Aashirvaad Salt 1kg',
    bool available = true,
  }) =>
      CatalogProductMatch(
        productMasterId: 101,
        name: name,
        isAvailableInCatalog: available,
        matchType: 'IDENTIFIER',
      );

  BarcodeResolution foundResolution({
    String barcode = '8901234567890',
    CatalogProductMatch? match,
  }) =>
      BarcodeResolution(
        status: BarcodeResolutionStatus.found,
        barcode: barcode,
        barcodeType: 'EAN-13',
        matches: [match ?? catalogMatch()],
      );
  group('BarcodeManualEntrySheet — manual add after a scan', () {
    testWidgets('accepts a 13-digit EAN-13 and looks it up', (tester) async {
      final repo = FakeBarcodeRepo();
      await openSheet(
        tester,
        sheet: const BarcodeManualEntrySheet(),
        repo: repo,
      );

      await tester.enterText(find.byType(TextFormField), '8901234567890');
      await tester.tap(find.text('Look up'));
      await tester.pumpAndSettle();

      // EAN-13 is the most common retail barcode in India and the field's own
      // hint example — it must reach the backend, not trip the validator.
      expect(find.text('Enter 8, 12, 13 or 14 digits'), findsNothing);
      expect(repo.lastBarcode, '8901234567890');
      expect(find.byType(BarcodeManualEntrySheet), findsNothing);
    });

    for (final (format, code) in const [
      ('EAN-8', '89012345'),
      ('UPC-A', '890123456789'),
      ('EAN-13', '8901234567890'),
      ('GTIN-14', '89012345678901'),
    ]) {
      testWidgets('accepts $format ($code)', (tester) async {
        final repo = FakeBarcodeRepo();
        await openSheet(
          tester,
          sheet: const BarcodeManualEntrySheet(),
          repo: repo,
        );

        await tester.enterText(find.byType(TextFormField), code);
        await tester.tap(find.text('Look up'));
        await tester.pumpAndSettle();

        expect(repo.lastBarcode, code);
      });
    }

    testWidgets('strips the separators printed around a code', (tester) async {
      final repo = FakeBarcodeRepo();
      await openSheet(
        tester,
        sheet: const BarcodeManualEntrySheet(),
        repo: repo,
      );

      // Mirrors the backend's normalize_barcode before it validates digits.
      await tester.enterText(find.byType(TextFormField), '890-1234 567890');
      await tester.tap(find.text('Look up'));
      await tester.pumpAndSettle();

      expect(repo.lastBarcode, '8901234567890');
    });

    testWidgets('rejects a code that is not a retail barcode length',
        (tester) async {
      final repo = FakeBarcodeRepo();
      await openSheet(
        tester,
        sheet: const BarcodeManualEntrySheet(),
        repo: repo,
      );

      await tester.enterText(find.byType(TextFormField), '89012345678'); // 11
      await tester.tap(find.text('Look up'));
      await tester.pumpAndSettle();

      expect(find.text('Enter 8, 12, 13 or 14 digits'), findsOneWidget);
      expect(repo.lastBarcode, isNull); // never reached the backend
    });

    testWidgets('rejects non-numeric input', (tester) async {
      final repo = FakeBarcodeRepo();
      await openSheet(
        tester,
        sheet: const BarcodeManualEntrySheet(),
        repo: repo,
      );

      await tester.enterText(find.byType(TextFormField), '89O1234567890');
      await tester.tap(find.text('Look up'));
      await tester.pumpAndSettle();

      expect(find.text('Enter 8, 12, 13 or 14 digits'), findsOneWidget);
      expect(repo.lastBarcode, isNull);
    });
  });

  group('BarcodeNotFoundSheet — product not found', () {
    testWidgets('names the miss, echoes the code and offers both ways out',
        (tester) async {
      var retried = 0;
      var manual = 0;
      await openSheet(
        tester,
        sheet: BarcodeNotFoundSheet(
          barcode: '999999999999',
          onTryAgain: () => retried++,
          onEnterManually: () => manual++,
        ),
      );

      expect(find.text('Product not found'), findsOneWidget);
      expect(find.text('No catalog product matches barcode 999999999999.'),
          findsOneWidget);
      // Nothing is invented for a code the catalog does not know; the sheet
      // points at the two real ways forward instead.
      expect(find.byType(ListTile), findsNothing);
      expect(find.text('Try Again'), findsOneWidget);
      expect(find.text('Enter Manually'), findsOneWidget);

      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();
      expect(retried, 1);

      await tester.tap(find.text('Enter Manually'));
      await tester.pumpAndSettle();
      expect(manual, 1);
    });
  });

  group('BarcodeConfirmSheet — barcode conflict', () {
    testWidgets('a 409 (already in inventory) offers an escape, not a dead end',
        (tester) async {
      final repo = FakeBarcodeRepo(
        onSave: (_) async => throw const ApiException(
          statusCode: 409,
          message: 'This product is already in your inventory — '
              'update it instead',
        ),
      );
      await openSheet(
        tester,
        repo: repo,
        sheet: BarcodeConfirmSheet(
          resolution: foundResolution(),
          selectedMatch: catalogMatch(),
          onSaved: () {},
        ),
      );

      await tester.enterText(find.byType(TextFormField).first, '85');
      await tester.tap(find.text('Add to inventory'));
      await tester.pumpAndSettle();

      expect(repo.lastPayload?.productMasterId, 101);
      expect(
          find.text('This product is already in your inventory'), findsOneWidget);
      expect(find.text('View products'), findsOneWidget);
      // The sheet stays open so the entry can be corrected or abandoned.
      expect(find.byType(BarcodeConfirmSheet), findsOneWidget);

      // Let the snackbar time out so no timer outlives the test.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('requires a selling price before it saves', (tester) async {
      final repo = FakeBarcodeRepo();
      await openSheet(
        tester,
        repo: repo,
        sheet: BarcodeConfirmSheet(
          resolution: foundResolution(),
          selectedMatch: catalogMatch(),
          onSaved: () {},
        ),
      );

      await tester.tap(find.text('Add to inventory'));
      await tester.pumpAndSettle();

      expect(find.text('Required'), findsOneWidget);
      expect(repo.lastPayload, isNull);
    });

    testWidgets('saves the scanned barcode and reports the created product',
        (tester) async {
      final repo = FakeBarcodeRepo();
      var saved = 0;
      await openSheet(
        tester,
        repo: repo,
        sheet: BarcodeConfirmSheet(
          resolution: foundResolution(),
          selectedMatch: catalogMatch(),
          onSaved: () => saved++,
        ),
      );

      await tester.enterText(find.byType(TextFormField).first, '85');
      await tester.tap(find.text('Add to inventory'));
      await tester.pumpAndSettle();

      expect(saved, 1);
      expect(repo.lastPayload?.barcode, '8901234567890');
      expect(repo.lastPayload?.price, 85);
    });
  });
}