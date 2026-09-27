import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/domain/inventory_scope.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/presentation/screens/inventory_dashboard_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/presentation/screens/inventory_list_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/presentation/screens/inventory_sync_status_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/presentation/screens/stock_history_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/presentation/screens/update_stock_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/presentation/controllers/import_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/presentation/screens/import_center_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/presentation/screens/import_history_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/presentation/screens/import_preview_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/presentation/screens/import_processing_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/presentation/screens/import_upload_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/data/import_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/domain/import_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/offers/domain/offer_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/offers/data/offers_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/pricing/presentation/screens/create_offer_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/pricing/presentation/screens/offer_details_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/pricing/presentation/screens/offer_list_screens.dart';
import 'package:hyperlocal_shopkeeper_app/features/pricing/presentation/screens/price_history_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/pricing/presentation/screens/price_list_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/pricing/presentation/screens/update_price_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';

import 'fakes.dart';

/// Fake workbook picker/saver (same contracts as the import flow tests —
/// defined locally so test files stay independent).
class FakeWorkbookPicker implements WorkbookPickerService {
  FakeWorkbookPicker({this.workbook, this.shouldCancel = false});

  PickedWorkbook? workbook;
  bool shouldCancel;
  int calls = 0;

  @override
  Future<PickedWorkbook?> pick() async {
    calls++;
    if (shouldCancel) return null;
    return workbook ??
        const PickedWorkbook(path: '/tmp/test.xlsx', name: 'test.xlsx');
  }
}

class FakeWorkbookSaver implements WorkbookSaveService {
  FakeWorkbookSaver({this.shouldSave = true});

  bool shouldSave;
  int calls = 0;
  final List<String> savedNames = [];

  @override
  Future<bool> saveWorkbook(String fileName, Uint8List bytes) async {
    calls++;
    savedNames.add(fileName);
    return shouldSave;
  }
}

/// INVENTORY / PRICING / IMPORT screen suite — the module screens introduced
/// with the screen inventory (dashboard, list scopes, stock, history, sync,
/// price list, update price, price history, offers, import center flow).
/// Only repositories/pickers are faked; controllers and widgets run for real.

ShopProductItem p({
  required int id,
  required String name,
  double price = 10,
  double? mrp,
  String? sku,
  int quantity = 5,
  String stockStatus = 'IN_STOCK',
  String? source,
  String? freshnessStatus,
  DateTime? lastUpdated,
}) =>
    ShopProductItem(
      id: id,
      name: name,
      status: 'ACTIVE',
      price: price,
      mrp: mrp,
      sku: sku,
      isActive: true,
      isAvailable: quantity > 0,
      quantity: quantity,
      stockStatus: stockStatus,
      source: source,
      freshnessStatus: freshnessStatus,
      lastUpdated: lastUpdated,
    );

ProviderContainer makeContainer({
  FakeProductRepo? productRepo,
  FakeOffersRepo? offersRepo,
  FakeImportRepo? importRepo,
  FakeWorkbookPicker? picker,
  FakeWorkbookSaver? saver,
}) {
  return ProviderContainer(
    overrides: [
      if (productRepo != null) ...[
        productRepositoryProvider.overrideWithValue(productRepo),
        inventoryRepositoryProvider.overrideWithValue(productRepo),
      ],
      if (offersRepo != null) offersRepositoryProvider.overrideWithValue(offersRepo),
      if (importRepo != null)
        inventoryImportRepositoryProvider.overrideWithValue(importRepo),
      if (picker != null) workbookPickerProvider.overrideWithValue(picker),
      if (saver != null) workbookSaveProvider.overrideWithValue(saver),
      tokenStoreProvider.overrideWithValue(
        InMemoryTokenStore(accessToken: 'test-access-token'),
      ),
      selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
    ],
  );
}

Future<void> pumpScreen(
  WidgetTester tester,
  ProviderContainer container,
  Widget screen,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // ── INVENTORY ──────────────────────────────────────────────────────────────
  group('InventoryDashboardScreen', () {
    testWidgets('renders stock-health stats and navigation tiles',
        (tester) async {
      final repo = FakeProductRepo(items: [
        p(id: 1, name: 'Rice 5kg', quantity: 40, source: 'EXCEL_UPLOAD'),
        p(
          id: 2,
          name: 'Oil 1L',
          quantity: 2,
          stockStatus: 'LOW_STOCK',
          source: 'MANUAL',
        ),
        p(
          id: 3,
          name: 'Bread',
          quantity: 0,
          stockStatus: 'OUT_OF_STOCK',
          source: 'BARCODE_SCAN',
        ),
      ]);
      final container = makeContainer(productRepo: repo);
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const InventoryDashboardScreen());

      expect(find.byKey(const Key('stat-total-products')), findsOneWidget);
      expect(find.byKey(const Key('stat-low-stock')), findsOneWidget);
      expect(find.byKey(const Key('stat-out-of-stock')), findsOneWidget);
      expect(
          find.byKey(const Key('inventory-tile-list')), findsOneWidget);
      expect(
          find.byKey(const Key('inventory-tile-low-stock')), findsOneWidget);
      expect(find.byKey(const Key('inventory-tile-out-of-stock')),
          findsOneWidget);
      expect(find.byKey(const Key('inventory-tile-freshness')),
          findsOneWidget);
      expect(find.byKey(const Key('inventory-tile-sync-status')),
          findsOneWidget);
      expect(find.byKey(const Key('inventory-tile-update-stock')),
          findsOneWidget);
      expect(find.byKey(const Key('inventory-tile-stock-history')),
          findsOneWidget);
      expect(find.byKey(const Key('inventory-tile-price-list')),
          findsOneWidget);
      expect(find.byKey(const Key('inventory-tile-import-center')),
          findsOneWidget);
    });
  });

  group('InventoryScopeScreen (list / low / out / freshness)', () {
    final items = [
      p(id: 1, name: 'Rice 5kg', quantity: 40),
      p(id: 2, name: 'Oil 1L', quantity: 2, stockStatus: 'LOW_STOCK'),
      p(id: 3, name: 'Bread', quantity: 0, stockStatus: 'OUT_OF_STOCK'),
    ];

    testWidgets('list view shows every product with a counter',
        (tester) async {
      final container = makeContainer(
        productRepo: FakeProductRepo(items: items),
      );
      addTearDown(container.dispose);
      await pumpScreen(tester, container,
          const InventoryScopeScreen(scope: InventoryScope.all));

      expect(find.byKey(const Key('inventory-count')), findsOneWidget);
      expect(find.text('3 of 3 products'), findsOneWidget);
      expect(find.text('Rice 5kg'), findsOneWidget);
      expect(find.text('Oil 1L'), findsOneWidget);
      expect(find.text('Bread'), findsOneWidget);
    });

    testWidgets('low stock view filters to LOW_STOCK rows', (tester) async {
      final container = makeContainer(
        productRepo: FakeProductRepo(items: items),
      );
      addTearDown(container.dispose);
      await pumpScreen(tester, container,
          const InventoryScopeScreen(scope: InventoryScope.low));

      expect(find.text('1 of 3 products'), findsOneWidget);
      expect(find.text('Oil 1L'), findsOneWidget);
      expect(find.text('Rice 5kg'), findsNothing);
    });

    testWidgets('out of stock view filters to OUT_OF_STOCK rows',
        (tester) async {
      final container = makeContainer(
        productRepo: FakeProductRepo(items: items),
      );
      addTearDown(container.dispose);
      await pumpScreen(tester, container,
          const InventoryScopeScreen(scope: InventoryScope.outOfStock));

      expect(find.text('1 of 3 products'), findsOneWidget);
      expect(find.text('Bread'), findsOneWidget);
      expect(find.text('Rice 5kg'), findsNothing);
    });

    testWidgets('freshness view surfaces stale items with labels',
        (tester) async {
      final container = makeContainer(
        productRepo: FakeProductRepo(items: [
          p(
            id: 1,
            name: 'Fresh Item',
            freshnessStatus: 'RECENTLY_UPDATED',
            lastUpdated: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
          p(id: 2, name: 'Old Item', freshnessStatus: 'STALE'),
        ]),
      );
      addTearDown(container.dispose);
      await pumpScreen(tester, container,
          const InventoryScopeScreen(scope: InventoryScope.freshness));

      expect(find.text('Old Item'), findsOneWidget);
      expect(find.text('Fresh Item'), findsOneWidget);
      expect(find.textContaining('Needs update'), findsWidgets);
      // The row age speaks the app-wide freshness vocabulary
      // (DateTimeUtils.formatInventoryFreshness), not a screen-local format.
      expect(find.textContaining('Inventory updated 5 min ago'), findsOneWidget);
    });
  });

  group('UpdateStockScreen', () {
    testWidgets('applies a delta adjustment through the audit endpoint',
        (tester) async {
      final repo = FakeProductRepo(items: [
        p(id: 11, name: 'Rice 5kg', quantity: 5),
      ]);
      final container = makeContainer(productRepo: repo);
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const UpdateStockScreen());

      // Picker mode first — choose the product.
      await tester.tap(find.text('Rice 5kg'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('update-stock-delta')), '5');
      await tester.tap(find.byKey(const Key('update-stock-save')));
      await tester.pumpAndSettle();

      expect(repo.adjustStockCalls, 1);
      expect(repo.lastAdjustedId, 11);
      expect(repo.lastAdjustPayload?['quantity_adjustment'], 5);
      expect(repo.lastAdjustPayload?['adjustment_type'], 'CORRECTION');
      expect(find.textContaining('5 → 10 units'), findsOneWidget);
    });

    testWidgets('rejects a zero delta with a readable message',
        (tester) async {
      final repo = FakeProductRepo(items: [
        p(id: 11, name: 'Rice 5kg', quantity: 5),
      ]);
      final container = makeContainer(productRepo: repo);
      addTearDown(container.dispose);

      await pumpScreen(
        tester,
        container,
        UpdateStockScreen(product: p(id: 11, name: 'Rice 5kg', quantity: 5)),
      );

      await tester.enterText(find.byKey(const Key('update-stock-delta')), '0');
      await tester.tap(find.byKey(const Key('update-stock-save')));
      await tester.pumpAndSettle();

      expect(repo.adjustStockCalls, 0);
      expect(find.byKey(const Key('update-stock-error')), findsOneWidget);
    });
  });

  group('StockHistoryScreen', () {
    testWidgets('renders movements, adjustments and price changes',
        (tester) async {
      final repo = FakeProductRepo(
        items: [p(id: 11, name: 'Rice 5kg', quantity: 5)],
        onHistory: (_, _, _) => ProductHistoryResult(
          shopProductId: 11,
          entries: [
            const ProductHistoryEntry(
              type: 'movement',
              quantityChange: 24,
              quantityBefore: 5,
              quantityAfter: 29,
              movementType: 'PURCHASE',
              source: 'EXCEL_UPLOAD',
            ),
            const ProductHistoryEntry(
              type: 'adjustment',
              quantityAdjustment: -3,
              adjustmentType: 'DAMAGE',
              reason: 'Broken bags',
            ),
            const ProductHistoryEntry(
              type: 'price_change',
              oldPrice: 100,
              newPrice: 90,
              oldMrp: 120,
              newMrp: 110,
              changeSource: 'MANUAL',
            ),
          ],
        ),
      );
      final container = makeContainer(productRepo: repo);
      addTearDown(container.dispose);

      await pumpScreen(
        tester,
        container,
        StockHistoryScreen(product: p(id: 11, name: 'Rice 5kg')),
      );

      expect(repo.historyCalls, 1);
      expect(repo.lastHistoryProductId, 11);
      expect(find.textContaining('+24 units'), findsOneWidget);
      expect(find.textContaining('5 → 29 units'), findsOneWidget);
      expect(find.textContaining('-3 units'), findsOneWidget);
      expect(find.text('Broken bags'), findsOneWidget);
      expect(find.textContaining('₹100 → ₹90'), findsOneWidget);
      expect(find.textContaining('MRP ₹120 → ₹110'), findsOneWidget);
    });
  });

  group('InventorySyncStatusScreen', () {
    testWidgets('groups products by inventory source', (tester) async {
      final container = makeContainer(
        productRepo: FakeProductRepo(items: [
          p(id: 1, name: 'A', source: 'EXCEL_UPLOAD',
              lastUpdated: DateTime(2026, 9, 1)),
          p(id: 2, name: 'B', source: 'EXCEL_UPLOAD',
              lastUpdated: DateTime(2026, 9, 2)),
          p(id: 3, name: 'C', source: 'BARCODE_SCAN',
              lastUpdated: DateTime(2026, 9, 3)),
        ]),
      );
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const InventorySyncStatusScreen());

      expect(find.text('Excel import'), findsWidgets);
      expect(find.text('Barcode scan'), findsWidgets);
      expect(find.byKey(const Key('sync-last-update')), findsOneWidget);
    });
  });

  // ── PRICING ────────────────────────────────────────────────────────────────
  group('PriceListScreen', () {
    testWidgets('renders price rows with MRP and implied discount',
        (tester) async {
      final container = makeContainer(
        productRepo: FakeProductRepo(items: [
          p(id: 1, name: 'Rice 5kg', price: 90, mrp: 120),
          p(id: 2, name: 'Oil 1L', price: 150),
        ]),
      );
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const PriceListScreen());

      expect(find.text('₹90'), findsOneWidget);
      expect(find.text('₹150'), findsOneWidget);
      expect(find.textContaining('25% off'), findsOneWidget);
      expect(find.textContaining('No MRP set'), findsOneWidget);
      // No timestamps on these rows → no freshness line (never a lone
      // "Price not updated yet" under every product).
      expect(find.textContaining('Price updated'), findsNothing);
    });

    testWidgets('shows a unified freshness line, amber once stale',
        (tester) async {
      final container = makeContainer(
        productRepo: FakeProductRepo(items: [
          p(
            id: 1,
            name: 'Rice 5kg',
            price: 90,
            lastUpdated: DateTime.now().subtract(const Duration(days: 2)),
          ),
          p(
            id: 2,
            name: 'Oil 1L',
            price: 150,
            lastUpdated: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
        ]),
      );
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const PriceListScreen());

      // Both rows speak the shared freshness vocabulary…
      expect(find.textContaining('Price updated'), findsNWidgets(2));
      expect(find.textContaining('Price updated 5 min ago'), findsOneWidget);
      // …and only the >24h row carries the stale indicator (amber weight).
      final staleTexts = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) =>
              (t.data ?? '').startsWith('Price updated') &&
              t.style?.fontWeight == FontWeight.w600)
          .toList();
      expect(staleTexts, hasLength(1));
      expect(staleTexts.single.data, isNot(contains('5 min ago')));
    });
  });

  group('UpdatePriceScreen', () {
    testWidgets('saves the new price and MRP through the products PATCH',
        (tester) async {
      final repo = FakeProductRepo(
        items: [p(id: 11, name: 'Rice 5kg', price: 90)],
      );
      final container = makeContainer(productRepo: repo);
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const UpdatePriceScreen());

      await tester.tap(find.text('Rice 5kg'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('update-price-field')), '95');
      await tester.enterText(
          find.byKey(const Key('update-price-mrp-field')), '120');
      await tester.tap(find.byKey(const Key('update-price-save')));
      await tester.pumpAndSettle();

      expect(repo.lastUpdatedId, 11);
      expect(repo.lastUpdateFields?['price'], 95.0);
      expect(repo.lastUpdateFields?['mrp'], 120.0);
      expect(find.byKey(const Key('update-price-success')), findsOneWidget);

      // Let the snackbar time out so no timer outlives the test.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('rejects an MRP lower than the selling price',
        (tester) async {
      final repo = FakeProductRepo(
        items: [p(id: 11, name: 'Rice 5kg', price: 90)],
      );
      final container = makeContainer(productRepo: repo);
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const UpdatePriceScreen());

      await tester.tap(find.text('Rice 5kg'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('update-price-field')), '95');
      await tester.enterText(
          find.byKey(const Key('update-price-mrp-field')), '50');
      await tester.tap(find.byKey(const Key('update-price-save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('update-price-error')), findsOneWidget);
      expect(repo.lastUpdatedId, isNull);
    });
  });

  group('PriceHistoryScreen', () {
    testWidgets('shows only price_change entries', (tester) async {
      final repo = FakeProductRepo(
        items: [p(id: 11, name: 'Rice 5kg', price: 90)],
        onHistory: (_, _, _) => ProductHistoryResult(
          shopProductId: 11,
          entries: [
            const ProductHistoryEntry(
              type: 'movement',
              quantityChange: 24,
            ),
            const ProductHistoryEntry(
              type: 'price_change',
              oldPrice: 80,
              newPrice: 90,
              changeSource: 'MANUAL',
            ),
            const ProductHistoryEntry(
              type: 'price_change',
              newPrice: 80,
            ),
          ],
        ),
      );
      final container = makeContainer(productRepo: repo);
      addTearDown(container.dispose);

      await pumpScreen(
        tester,
        container,
        PriceHistoryScreen(product: p(id: 11, name: 'Rice 5kg', price: 90)),
      );

      expect(find.textContaining('₹80 → ₹90'), findsOneWidget);
      expect(find.textContaining('via MANUAL'), findsOneWidget);
      expect(find.textContaining('+24 units'), findsNothing);
    });
  });

  group('Offer screens', () {
    testWidgets('active offers lists open offers, expired lists closed ones',
        (tester) async {
      final repo = FakeOffersRepo(
        page: OfferListPage(
          items: [
            offerSummary(id: 1, title: 'Live Offer', status: 'ACTIVE'),
            offerSummary(id: 2, title: 'Old Offer', status: 'EXPIRED'),
          ],
          count: 2,
        ),
      );
      final container = makeContainer(offersRepo: repo);
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const ActiveOffersScreen());
      expect(find.text('Live Offer'), findsOneWidget);
      expect(find.text('Old Offer'), findsNothing);

      await pumpScreen(tester, container, const ExpiredOffersScreen());
      expect(find.text('Old Offer'), findsOneWidget);
      expect(find.text('Live Offer'), findsNothing);
      // ONE fetch served both screens (local slicing, no re-fetch).
      expect(repo.fetchCalls, 1);
    });

    testWidgets('offer details renders every server field', (tester) async {
      final offer = offerSummary(
        id: 9,
        title: 'Monsoon Sale',
        offerType: 'FLAT_DISCOUNT',
        discountPercentage: null,
        discountValue: 50,
        status: 'ACTIVE',
        productCount: 4,
      );
      final container = makeContainer();
      addTearDown(container.dispose);

      await pumpScreen(
        tester,
        container,
        OfferDetailsScreen(offer: offer),
      );

      expect(find.text('Monsoon Sale'), findsOneWidget);
      expect(find.textContaining('₹50 off'), findsWidgets);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('create offer validates, then assigns with selected products',
        (tester) async {
      final offersRepo = FakeOffersRepo();
      final container = makeContainer(
        offersRepo: offersRepo,
        productRepo: FakeProductRepo(items: [
          p(id: 31, name: 'Rice 5kg', price: 90),
          p(id: 32, name: 'Oil 1L', price: 150),
        ]),
      );
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const CreateOfferScreen());

      // Empty submit → first validation error.
      await tester.tap(find.byKey(const Key('offer-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('offer-field-error')), findsOneWidget);
      expect(offersRepo.assignCalls, 0);

      // Fill the form.
      await tester.enterText(
          find.byKey(const Key('offer-title-field')), 'Monsoon Sale');
      await tester.enterText(
          find.byKey(const Key('offer-discount-field')), '15');

      // Start date = today (dialog default).
      await tester.tap(find.byKey(const Key('offer-start-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // End date = day 28 of the visible month (strictly after start).
      await tester.tap(find.byKey(const Key('offer-end-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('28'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Select one product.
      await tester.tap(find.byKey(const Key('offer-product-31')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('offer-submit')));
      await tester.pumpAndSettle();

      expect(offersRepo.assignCalls, 1);
    });
  });

  // ── IMPORT ─────────────────────────────────────────────────────────────────
  group('ImportCenterScreen', () {
    testWidgets('shows the flow tiles and recent imports', (tester) async {
      final container = makeContainer(
        importRepo: FakeImportRepo(),
        saver: FakeWorkbookSaver(),
      );
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const ImportCenterScreen());

      expect(
          find.byKey(const Key('import-tile-download-sample')), findsOneWidget);
      // Excel path + history entry, keyed by the current hub design.
      expect(find.byKey(const Key('method-excel-csv')), findsOneWidget);
      expect(find.byKey(const Key('summary-last-import')), findsOneWidget);

      // Recent imports sit below the fold on the default 600px test viewport
      // (the ListView builds lazily), so scroll the row-count line into view.
      await tester.scrollUntilVisible(
        find.textContaining('5 valid, 0 errors'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Recent imports'), findsOneWidget);
      expect(find.text('last.xlsx'), findsOneWidget);
      expect(find.textContaining('5 valid, 0 errors'), findsOneWidget);
    });

    testWidgets('download sample offers the workbook save', (tester) async {
      final repo = FakeImportRepo();
      final saver = FakeWorkbookSaver();
      final container = makeContainer(importRepo: repo, saver: saver);
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const ImportCenterScreen());
      await tester.tap(find.byKey(const Key('import-tile-download-sample')));
      await tester.pumpAndSettle();

      expect(repo.sampleCalls, 1);
      expect(repo.lastSampleShopId, 10);
      expect(saver.calls, 1);
      expect(find.text('Sample workbook saved'), findsOneWidget);

      // Let the snackbar time out so no timer outlives the test.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  group('Import upload → preview → processing flow', () {
    Widget flowHarness(ProviderContainer container) {
      final router = GoRouter(
        initialLocation: '/import-upload',
        routes: [
          GoRoute(
            path: '/import-upload',
            builder: (_, _) => const ImportUploadScreen(),
          ),
          GoRoute(
            path: '/import-preview',
            builder: (_, _) => const ImportPreviewScreen(),
          ),
          GoRoute(
            path: '/import-processing',
            builder: (_, _) => const ImportProcessingScreen(),
          ),
          GoRoute(
            path: '/import-center',
            builder: (_, _) => const ImportCenterScreen(),
          ),
          GoRoute(
            path: '/import-history',
            builder: (_, _) => const ImportHistoryScreen(),
          ),
        ],
      );
      return UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      );
    }

    testWidgets('pick → upload progress → preview → apply → success',
        (tester) async {
      final container = makeContainer(
        importRepo: FakeImportRepo(
          onUpload: ImportPreview(
            meta: const ImportJob(
              id: 42,
              filename: 'stock.xlsx',
              status: 'VALIDATED',
              totalRows: 10,
              validRows: 8,
              errorRows: 2,
            ),
            rows: const [
              ImportRow(rowNumber: 1, status: 'VALID', productName: 'Rice'),
              ImportRow(
                rowNumber: 3,
                status: 'ERROR',
                errorCode: 'MISSING_PRICE',
                errorMessage: 'Price is required',
              ),
            ],
          ),
          onConfirm: const ImportConfirmResult(processed: 8, failed: 0),
        ),
        picker: FakeWorkbookPicker(),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(flowHarness(container));
      await tester.pumpAndSettle();

      // Step 1: pick the file.
      await tester.tap(find.byKey(const Key('import-pick-button')));
      await tester.pumpAndSettle();

      // Step 2: preview screen with summary chips and the error row.
      expect(find.text('Review import'), findsOneWidget);
      expect(find.text('stock.xlsx'), findsOneWidget);
      expect(find.textContaining('MISSING_PRICE'), findsOneWidget);

      // Errors-only toggle narrows the list.
      await tester.tap(find.byKey(const Key('import-errors-toggle')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Row 1'), findsNothing);
      expect(find.textContaining('Row 3'), findsOneWidget);

      // Step 3: confirm → processing → success.
      await tester.tap(find.byKey(const Key('import-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('import-result-success')), findsOneWidget);
      expect(find.text('8 rows processed — all successful.'), findsOneWidget);
      expect(find.byKey(const Key('import-result-view-results')), findsOneWidget);
    });

    testWidgets('partial success reports processed and failed counts',
        (tester) async {
      final container = makeContainer(
        importRepo: FakeImportRepo(
          onUpload: ImportPreview(
            meta: const ImportJob(
              id: 42,
              filename: 'stock.xlsx',
              status: 'VALIDATED',
              totalRows: 10,
              validRows: 6,
              errorRows: 4,
            ),
          ),
          onConfirm: const ImportConfirmResult(processed: 6, failed: 2),
        ),
        picker: FakeWorkbookPicker(),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(flowHarness(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import-pick-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('import-result-partial')), findsOneWidget);
      expect(
        find.text('8 rows processed — 6 successful, 2 failed.'),
        findsOneWidget,
      );
      // Partial results expose both drill-downs plus Done.
      expect(
        find.byKey(const Key('import-result-view-results')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('import-result-view-errors')), findsOneWidget);
      expect(find.byKey(const Key('import-result-done')), findsOneWidget);
    });

    testWidgets('queued imports point at the history', (tester) async {
      final container = makeContainer(
        importRepo: FakeImportRepo(
          onUpload: ImportPreview(
            meta: const ImportJob(
              id: 42,
              filename: 'stock.xlsx',
              status: 'VALIDATED',
              totalRows: 500,
              validRows: 500,
              errorRows: 0,
            ),
          ),
          onConfirm: const ImportConfirmResult(
            processed: 500,
            failed: 0,
            queued: true,
          ),
        ),
        picker: FakeWorkbookPicker(),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(flowHarness(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import-pick-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('import-result-queued')), findsOneWidget);
      expect(find.text('Import queued'), findsOneWidget);
    });
  });

  group('ImportHistoryScreen', () {
    testWidgets('lists past jobs and opens the row-level report',
        (tester) async {
      final container = makeContainer(
        importRepo: FakeImportRepo(
          onList: const [
            ImportJob(
              id: 7,
              filename: 'march.xlsx',
              status: 'PARTIAL',
              totalRows: 10,
              validRows: 8,
              errorRows: 2,
              // A PARTIAL job has been applied, so the tile reports the
              // processing outcome rather than the validation counters.
              processedRows: 8,
              failedRows: 2,
            ),
          ],
          onUpload: ImportPreview(
            meta: const ImportJob(
              id: 7,
              filename: 'march.xlsx',
              status: 'PARTIAL',
              totalRows: 10,
              validRows: 8,
              errorRows: 2,
              processedRows: 8,
              failedRows: 2,
            ),
            rows: const [
              ImportRow(rowNumber: 1, status: 'VALID', productName: 'Rice'),
              ImportRow(
                rowNumber: 4,
                status: 'ERROR',
                errorCode: 'UNKNOWN_PRODUCT',
                errorMessage: 'Product not found',
              ),
            ],
          ),
        ),
      );
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const ImportHistoryScreen());

      expect(find.text('march.xlsx'), findsOneWidget);
      // Status is rendered as shopkeeper copy, not the raw server enum.
      expect(find.text('Partial Success'), findsOneWidget);

      // Open the report sheet.
      await tester.tap(find.text('march.xlsx'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Row 1 · Rice'), findsOneWidget);
      expect(find.textContaining('UNKNOWN_PRODUCT'), findsOneWidget);
    });
  });
}
