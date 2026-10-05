import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/presentation/screens/update_stock_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/data/import_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/domain/import_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/presentation/controllers/import_controller.dart';

import 'fakes.dart';
import 'inventory_pricing_import_screens_test.dart' show makeContainer, p, pumpScreen;

/// Immediate feedback — the UI half of the data-validation contract.
///
/// The backend already rejects every one of these values; what is tested here is
/// that the shopkeeper is told BEFORE submitting. The evidence is always the
/// same shape: the message is on screen while the repository call count is still
/// zero, so a test cannot pass on a server rejection arriving late.
class _AlwaysPicks implements WorkbookPickerService {
  const _AlwaysPicks(this.workbook);

  final PickedWorkbook? workbook;

  @override
  Future<PickedWorkbook?> pick() async => workbook;
}

void main() {
  group('UpdateStockScreen gives feedback while typing', () {
    Future<ProviderContainer> stockScreen(WidgetTester tester) async {
      final repo = FakeProductRepo(
        items: [p(id: 11, name: 'Rice 5kg', quantity: 5)],
      );
      final container = makeContainer(productRepo: repo);
      addTearDown(container.dispose);
      await pumpScreen(tester, container, const UpdateStockScreen());
      await tester.tap(find.text('Rice 5kg'));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('a zero change is refused without pressing Save', (tester) async {
      await stockScreen(tester);

      expect(find.text('Enter a non-zero quantity change'), findsNothing);

      await tester.enterText(find.byKey(const Key('update-stock-delta')), '0');
      await tester.pumpAndSettle();

      // Visible WITHOUT tapping Save: that is the whole point.
      expect(find.text('Enter a non-zero quantity change'), findsOneWidget);
    });

    testWidgets('a fraction cannot even be typed in', (tester) async {
      await stockScreen(tester);

      await tester.enterText(find.byKey(const Key('update-stock-delta')), '2.5');
      await tester.pumpAndSettle();

      // The input formatter drops the decimal point, so the shopkeeper never
      // gets into the state where stock is fractional. Stronger than showing
      // them an error afterwards.
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('update-stock-delta')))
            .controller
            ?.text,
        '25',
      );
      expect(find.text('Enter a whole number'), findsNothing);
    });

    testWidgets('clearing the field clears the complaint', (tester) async {
      await stockScreen(tester);

      await tester.enterText(find.byKey(const Key('update-stock-delta')), '0');
      await tester.pumpAndSettle();
      expect(find.text('Enter a non-zero quantity change'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('update-stock-delta')), '4');
      await tester.pumpAndSettle();
      expect(find.text('Enter a non-zero quantity change'), findsNothing);
    });

    testWidgets('a valid change shows no complaint and still saves', (
      tester,
    ) async {
      final repo = FakeProductRepo(
        items: [p(id: 11, name: 'Rice 5kg', quantity: 5)],
      );
      final container = makeContainer(productRepo: repo);
      addTearDown(container.dispose);
      await pumpScreen(tester, container, const UpdateStockScreen());
      await tester.tap(find.text('Rice 5kg'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('update-stock-delta')), '-3');
      await tester.pumpAndSettle();

      // A negative adjustment removes stock, so it is valid.
      expect(find.text('Enter a non-zero quantity change'), findsNothing);
      await tester.tap(find.byKey(const Key('update-stock-save')));
      await tester.pumpAndSettle();
      expect(repo.adjustStockCalls, 1);
    });
  });

  group('The import refuses a workbook before uploading it', () {
    Future<ProviderContainer> importContainer(
      WidgetTester tester,
      FakeImportRepo repo,
      PickedWorkbook? workbook,
    ) async {
      final container = ProviderContainer(
        overrides: [
          inventoryImportRepositoryProvider.overrideWithValue(repo),
          workbookPickerProvider.overrideWithValue(_AlwaysPicks(workbook)),
          tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'tok'),
          ),
          selectedShopProvider.overrideWith(
            () => SelectedShopOverride(ownerShop()),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    testWidgets('an oversized workbook never reaches the network', (
      tester,
    ) async {
      final repo = FakeImportRepo();
      final container = await importContainer(
        tester,
        repo,
        const PickedWorkbook(
          path: '/tmp/big.xlsx',
          name: 'big.xlsx',
          sizeBytes: 8 * 1024 * 1024,
        ),
      );

      await container.read(importControllerProvider.notifier).pickAndUpload();

      expect(repo.uploadCalls, 0);
      final state = container.read(importControllerProvider);
      expect(state.status, ImportStatus.error);
      expect(state.message, contains('maximum'));
    });

    testWidgets('the wrong file type never reaches the network', (tester) async {
      final repo = FakeImportRepo();
      final container = await importContainer(
        tester,
        repo,
        const PickedWorkbook(path: '/tmp/stock.csv', name: 'stock.csv'),
      );

      await container.read(importControllerProvider.notifier).pickAndUpload();

      expect(repo.uploadCalls, 0);
      expect(container.read(importControllerProvider).message, contains('.xlsx'));
    });

    testWidgets('an unknown size is still uploaded for the server to judge', (
      tester,
    ) async {
      final repo = FakeImportRepo(
        onUpload: ImportPreview(
          meta: const ImportJob(
            id: 1,
            filename: 'stock.xlsx',
            status: 'AWAITING_CONFIRMATION',
            totalRows: 1,
            validRows: 1,
            errorRows: 0,
          ),
        ),
      );
      final container = await importContainer(
        tester,
        repo,
        const PickedWorkbook(path: '/tmp/stock.xlsx', name: 'stock.xlsx'),
      );

      await container.read(importControllerProvider.notifier).pickAndUpload();

      // Guessing a size the picker never reported would reject valid files.
      expect(repo.uploadCalls, 1);
      expect(
        container.read(importControllerProvider).status,
        ImportStatus.preview,
      );
    });
  });
}
