import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/app.dart';
import 'package:hyperlocal_shopkeeper_app/core/auth/firebase_auth_service.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/barcode/data/barcode_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/barcode/domain/barcode_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/barcode/presentation/controllers/barcode_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/barcode/presentation/widgets/barcode_sheets.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/data/dashboard_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/domain/dashboard_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/data/import_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/domain/import_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/data/notifications_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/domain/notification_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/controllers/products_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/widgets/product_sheets.dart';

import 'fakes.dart';

/// Req 21-27 coverage: dashboard priority signals, the manual-create
/// payload contract, and the Add-method chooser sheet.
///
/// Overrides follow the repo convention (inline provider overrides, see
/// dashboard_test.dart) with the token + selected-shop base pair repeated.
void main() {
  ProviderContainer makeContainer([List<dynamic> extraOverrides = const []]) {
    final container = ProviderContainer(overrides: [
      tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(accessToken: 'test-access-token')),
      selectedShopProvider
          .overrideWith(() => SelectedShopOverride(ownerShop(id: 10))),
      ...extraOverrides,
    ]);
    addTearDown(container.dispose);
    return container;
  }

  group('ProductStats.needs_attention (req 21)', () {
    test('parses the server-sorted flagged products', () {
      final stats = ProductStats.fromJson(const {
        'total': 5,
        'active': 4,
        'inactive': 1,
        'in_stock': 2,
        'low_stock': 2,
        'out_of_stock': 1,
        'total_units': 50,
        'needs_attention': [
          {
            'shop_product_id': 11,
            'name': 'Amul Milk 500ml',
            'quantity': 0,
            'stock_status': 'OUT_OF_STOCK',
          },
          {
            'shop_product_id': 12,
            'name': 'Parle-G 1kg',
            'quantity': 2,
            'stock_status': 'LOW_STOCK',
          },
        ],
      });
      expect(stats.needsAttention, hasLength(2));
      expect(stats.needsAttention.first.name, 'Amul Milk 500ml');
      expect(stats.needsAttention.first.isOutOfStock, isTrue);
      expect(stats.needsAttention.last.isOutOfStock, isFalse);
    });

    test('absent needs_attention parses to an empty list', () {
      final stats = ProductStats.fromJson(const {'total': 1});
      expect(stats.needsAttention, isEmpty);
    });
  });

  group('DashboardController priority signals (req 21)', () {
    test('collects failed import / stale / unread into the alerts state',
        () async {
      final container = makeContainer([
        dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepo()),
        inventoryImportRepositoryProvider.overrideWithValue(FakeImportRepo(
          onList: [
            const ImportJob(
              id: 3,
              filename: 'march.xlsx',
              status: 'FAILED',
              totalRows: 10,
              validRows: 0,
              errorRows: 10,
            ),
          ],
        )),
        notificationsRepositoryProvider.overrideWithValue(
            FakeNotificationsRepo(
                page: const NotificationsPage(items: [], unreadCount: 2))),
        productRepositoryProvider.overrideWithValue(FakeProductRepo(items: [
          const ShopProductItem(
            id: 1,
            name: 'Amul Milk',
            status: 'ACTIVE',
            price: 30,
            isActive: true,
            isAvailable: true,
            quantity: 0,
            stockStatus: 'OUT_OF_STOCK',
            freshnessStatus: 'STALE',
          ),
        ])),
      ]);

      await container.read(dashboardControllerProvider.notifier).load();

      final state = container.read(dashboardControllerProvider);
      expect(state.status, DashboardStatus.ready);
      expect(state.alerts.hasFailedImport, isTrue);
      expect(state.alerts.failedImportName, 'march.xlsx');
      expect(state.alerts.failedImportRows, 10);
      expect(state.alerts.staleCount, 1);
      expect(state.alerts.unreadNotifications, 2);
    });

    test('a healthy shop has empty alerts', () async {
      final container = makeContainer([
        dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepo()),
        inventoryImportRepositoryProvider.overrideWithValue(FakeImportRepo()),
        notificationsRepositoryProvider
            .overrideWithValue(FakeNotificationsRepo()),
        productRepositoryProvider.overrideWithValue(FakeProductRepo()),
      ]);

      await container.read(dashboardControllerProvider.notifier).load();

      final state = container.read(dashboardControllerProvider);
      expect(state.status, DashboardStatus.ready);
      expect(state.alerts.isEmpty, isTrue);
    });

    test('priority lookups fail soft — dashboard still loads', () async {
      final container = makeContainer([
        dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepo()),
        inventoryImportRepositoryProvider
            .overrideWithValue(FakeImportRepo(error: Exception('network'))),
        notificationsRepositoryProvider
            .overrideWithValue(FakeNotificationsRepo(error: Exception('x'))),
        productRepositoryProvider.overrideWithValue(FakeProductRepo()),
      ]);

      await container.read(dashboardControllerProvider.notifier).load();

      final state = container.read(dashboardControllerProvider);
      expect(state.status, DashboardStatus.ready);
      expect(state.alerts.isEmpty, isTrue);
    });
  });

  group('ProductsController.createProduct payload (req 25)', () {
    test('sends every ShopkeeperProductCreate field and never a barcode',
        () async {
      final repo = FakeProductRepo();
      final container =
          makeContainer([productRepositoryProvider.overrideWithValue(repo)]);

      final ok = await container
          .read(productsControllerProvider.notifier)
          .createProduct(
            name: 'Basmati Rice',
            price: 120,
            mrp: 140,
            unit: '1 kg',
            sku: 'SKU-1',
            brand: 'Daawat',
            description: 'Long grain',
            imageKey: 'products/img.jpg',
            isAvailable: false,
            quantity: 25,
            lowStockThreshold: 4,
            publish: false,
          );

      expect(ok, isTrue);
      final payload = repo.lastCreatePayload!;
      expect(payload['name'], 'Basmati Rice');
      expect(payload['price'], 120);
      expect(payload['mrp'], 140);
      expect(payload['unit'], '1 kg');
      expect(payload['sku'], 'SKU-1');
      expect(payload['brand_name'], 'Daawat');
      expect(payload['description'], 'Long grain');
      expect(payload['image_key'], 'products/img.jpg');
      expect(payload['is_available'], isFalse);
      expect(payload['quantity'], 25);
      expect(payload['low_stock_threshold'], 4);
      expect(payload['publish'], isFalse);
      // Barcodes only enter through the scanner flow — never this payload.
      expect(payload.containsKey('barcode'), isFalse);
    });

    test('omits empty optional fields from the payload', () async {
      final repo = FakeProductRepo();
      final container =
          makeContainer([productRepositoryProvider.overrideWithValue(repo)]);

      final ok = await container
          .read(productsControllerProvider.notifier)
          .createProduct(name: 'Salt', price: 20, publish: true);

      expect(ok, isTrue);
      final payload = repo.lastCreatePayload!;
      expect(payload.containsKey('unit'), isFalse);
      expect(payload.containsKey('sku'), isFalse);
      expect(payload.containsKey('brand_name'), isFalse);
      expect(payload.containsKey('description'), isFalse);
      expect(payload.containsKey('image_key'), isFalse);
      expect(payload['quantity'], 0);
      expect(payload['is_available'], isTrue);
    });

    test('saveEdits PATCHes the product image key', () async {
      final repo = FakeProductRepo();
      final container =
          makeContainer([productRepositoryProvider.overrideWithValue(repo)]);

      final ok = await container
          .read(productsControllerProvider.notifier)
          .saveEdits(productId: 5, imageKey: 'products/new.jpg');

      expect(ok, isTrue);
      expect(repo.lastUpdatedId, 5);
      expect(repo.lastUpdateFields!['image_key'], 'products/new.jpg');
    });
  });

  group('ProductAddMethodSheet (req 24)', () {
    testWidgets('offers manual / barcode / excel and keeps POS disabled',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => const ProductAddMethodSheet(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Enter manually'), findsOneWidget);
      expect(find.text('Scan barcode'), findsOneWidget);
      expect(find.text('Bulk Excel import'), findsOneWidget);
      // POS stays visible but unusable until POS integration ships.
      final posTile =
          tester.widget<ListTile>(find.widgetWithText(ListTile, 'POS sync'));
      expect(posTile.enabled, isFalse);
      expect(posTile.onTap, isNull);
    });

    testWidgets('manual entry opens the full create form', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => const ProductAddMethodSheet(),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enter manually'));
      await tester.pumpAndSettle();

      // The manual form (req 25) opens with the full field set.
      expect(find.text('New product'), findsOneWidget);
      expect(find.text('Product name *'), findsOneWidget);
      expect(find.text('More details (optional)'), findsOneWidget);
    });
  });

  group('Dashboard priority card (req 21, widget)', () {
    Widget appFor(ProviderContainer container) {
      return UncontrolledProviderScope(
        container: container,
        child: const ShopkeeperApp(),
      );
    }

    void setWindowSize(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('renders priority rows from real backend data',
        (tester) async {
      final json = dashboardJson();
      // Rebuild the nested map so the needs_attention list can be added
      // without fighting the fixture's reified map types.
      final products = Map<String, dynamic>.from(json['products'] as Map);
      products['needs_attention'] = [
        {
          'shop_product_id': 1,
          'name': 'Amul Milk 500ml',
          'quantity': 0,
          'stock_status': 'OUT_OF_STOCK',
        },
        {
          'shop_product_id': 2,
          'name': 'Parle-G 1kg',
          'quantity': 2,
          'stock_status': 'LOW_STOCK',
        },
        {
          'shop_product_id': 3,
          'name': 'Sugar 1kg',
          'quantity': 1,
          'stock_status': 'LOW_STOCK',
        },
        {
          'shop_product_id': 4,
          'name': 'Tea 250g',
          'quantity': 3,
          'stock_status': 'LOW_STOCK',
        },
      ];
      json['products'] = products;
      final container = ProviderContainer(overrides: [
        dashboardRepositoryProvider
            .overrideWithValue(FakeDashboardRepo(json: json)),
        inventoryImportRepositoryProvider.overrideWithValue(FakeImportRepo(
          onList: [
            const ImportJob(
              id: 3,
              filename: 'march.xlsx',
              status: 'FAILED',
              totalRows: 10,
              validRows: 0,
              errorRows: 10,
            ),
          ],
        )),
        notificationsRepositoryProvider.overrideWithValue(
            FakeNotificationsRepo(
                page: const NotificationsPage(items: [], unreadCount: 2))),
        productRepositoryProvider.overrideWithValue(FakeProductRepo(items: [
          const ShopProductItem(
            id: 1,
            name: 'Amul Milk',
            status: 'ACTIVE',
            price: 30,
            isActive: true,
            isAvailable: true,
            quantity: 0,
            stockStatus: 'OUT_OF_STOCK',
            freshnessStatus: 'STALE',
          ),
        ])),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        authRepositoryProvider
            .overrideWithValue(FakeAuthRepository()..restoreResult = makeSession()),
        firebaseAuthServiceProvider
            .overrideWithValue(FakeFirebaseAuthService()),
      ]);
      addTearDown(container.dispose);
      setWindowSize(tester);

      await tester.pumpWidget(appFor(container));
      await tester.pumpAndSettle();

      // Fixed priority order: low stock -> failed import -> stale ->
      // notification -> profile setup, each backed by real data.
      expect(find.text('Needs attention'), findsOneWidget);
      // The inventory stat card also says "Low stock" — so require the
      // priority row to exist, not to be unique.
      expect(find.text('Low stock'), findsWidgets);
      // Flagged product names surface on the row (backend-sorted).
      expect(find.textContaining('Amul Milk 500ml'), findsOneWidget);
      expect(find.textContaining('Parle-G 1kg'), findsOneWidget);
      expect(find.text('Failed import'), findsOneWidget);
      expect(find.text('Inventory stale'), findsOneWidget);
      expect(find.text('Important notification'), findsOneWidget);
      expect(find.text('Profile setup issue'), findsOneWidget);
    });

    testWidgets('hides the priority card when nothing needs attention',
        (tester) async {
      final json = dashboardJson()
        ..['shop'] = {
          'id': 10,
          'name': 'Kirana Corner',
          'status': 'REGISTERED',
          'is_verified': true,
        }
        ..['products'] = {
          'total': 5,
          'active': 5,
          'inactive': 0,
          'in_stock': 5,
          'low_stock': 0,
          'out_of_stock': 0,
          'total_units': 50,
        };
      final container = ProviderContainer(overrides: [
        dashboardRepositoryProvider
            .overrideWithValue(FakeDashboardRepo(json: json)),
        inventoryImportRepositoryProvider.overrideWithValue(FakeImportRepo()),
        notificationsRepositoryProvider
            .overrideWithValue(FakeNotificationsRepo()),
        productRepositoryProvider.overrideWithValue(FakeProductRepo()),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        authRepositoryProvider
            .overrideWithValue(FakeAuthRepository()..restoreResult = makeSession()),
        firebaseAuthServiceProvider
            .overrideWithValue(FakeFirebaseAuthService()),
      ]);
      addTearDown(container.dispose);
      setWindowSize(tester);

      await tester.pumpWidget(appFor(container));
      await tester.pumpAndSettle();

      // No signals -> no priority card at all (nothing fabricated). The
      // inventory stat card still renders its own "Low stock" label, so
      // assert on the card title and the priority-only rows.
            expect(find.text('Needs attention'), findsNothing);
      expect(find.text('Failed import'), findsNothing);
      expect(find.text('Inventory stale'), findsNothing);
      expect(find.text('Profile setup issue'), findsNothing);
    });
  });

  // ── Req 26/27 — Barcode scanner flow & edge cases ──────────────────────────

  group('BarcodeController.resolve (req 26/27)', () {
    test('FOUND status renders resolved with one match', () async {
      final container = makeContainer([
        barcodeRepositoryProvider.overrideWithValue(FakeBarcodeRepo()),
      ]);
      final controller = container.read(barcodeControllerProvider.notifier);

      await controller.resolve('8901234567890');

      final state = container.read(barcodeControllerProvider);
      expect(state.status, BarcodeScanStatus.resolved);
      expect(state.resolution!.status, BarcodeResolutionStatus.found);
      expect(state.resolution!.matches, hasLength(1));
      expect(state.resolution!.matches.first.name, 'Aashirvaad Salt 1kg');
    });

    test('NOT_FOUND maps to resolved state with no matches', () async {
      final container = makeContainer([
        barcodeRepositoryProvider.overrideWithValue(FakeBarcodeRepo(
          onResolve: BarcodeResolution(
            status: BarcodeResolutionStatus.notFound,
            barcode: '0000000000015',
          ),
        )),
      ]);
      final controller = container.read(barcodeControllerProvider.notifier);

      await controller.resolve('0000000000015');

      final state = container.read(barcodeControllerProvider);
      expect(state.status, BarcodeScanStatus.resolved);
      expect(state.resolution!.status, BarcodeResolutionStatus.notFound);
      expect(state.resolution!.matches, isEmpty);
    });

    test('INVALID status is surfaced (not thrown)', () async {
      final container = makeContainer([
        barcodeRepositoryProvider.overrideWithValue(FakeBarcodeRepo(
          onResolve: BarcodeResolution(
            status: BarcodeResolutionStatus.invalid,
            barcode: 'bad',
            errorCode: 'INVALID_BARCODE',
            message: 'Barcode format not recognized',
          ),
        )),
      ]);
      final controller = container.read(barcodeControllerProvider.notifier);

      await controller.resolve('bad');

      final state = container.read(barcodeControllerProvider);
      expect(state.status, BarcodeScanStatus.resolved);
      expect(state.resolution!.status, BarcodeResolutionStatus.invalid);
    });

    test('MULTIPLE_MATCHES returns all matches for disambiguation', () async {
      final container = makeContainer([
        barcodeRepositoryProvider.overrideWithValue(FakeBarcodeRepo(
          onResolve: BarcodeResolution(
            status: BarcodeResolutionStatus.multipleMatches,
            barcode: '8901234567890',
            message: 'Barcode shared by 2 products',
            matches: const [
              CatalogProductMatch(
                productMasterId: 101,
                name: 'Amul Milk 500ml',
                brand: 'Amul',
                isAvailableInCatalog: true,
                matchType: 'IDENTIFIER',
              ),
              CatalogProductMatch(
                productMasterId: 102,
                name: 'Amul Milk 1L',
                brand: 'Amul',
                isAvailableInCatalog: true,
                matchType: 'IDENTIFIER',
              ),
            ],
          ),
        )),
      ]);
      final controller = container.read(barcodeControllerProvider.notifier);

      await controller.resolve('8901234567890');

      final state = container.read(barcodeControllerProvider);
      expect(state.status, BarcodeScanStatus.resolved);
      expect(state.resolution!.status, BarcodeResolutionStatus.multipleMatches);
      expect(state.resolution!.matches, hasLength(2));
    });

    test('serviceUnavailable is mapped to the resolved state', () async {
      final container = makeContainer([
        barcodeRepositoryProvider.overrideWithValue(FakeBarcodeRepo(
          onResolve: BarcodeResolution(
            status: BarcodeResolutionStatus.serviceUnavailable,
            barcode: '8901234567890',
            message: 'Service unavailable',
          ),
        )),
      ]);
      final controller = container.read(barcodeControllerProvider.notifier);

      await controller.resolve('8901234567890');

      final state = container.read(barcodeControllerProvider);
      expect(state.status, BarcodeScanStatus.resolved);
      expect(state.resolution!.status,
          BarcodeResolutionStatus.serviceUnavailable);
    });

    test('network failure (thrown exception) lands in error state', () async {
      final container = makeContainer([
        barcodeRepositoryProvider.overrideWithValue(FakeBarcodeRepo(
          error: ApiException(message: 'No internet connection'),
        )),
      ]);
      final controller = container.read(barcodeControllerProvider.notifier);

      await controller.resolve('8901234567890');

      final state = container.read(barcodeControllerProvider);
      expect(state.status, BarcodeScanStatus.error);
      expect(state.message, contains('internet'));
    });

    test('saveFromScan succeeds and resets to idle', () async {
      final repo = FakeBarcodeRepo();
      final container = makeContainer([
        barcodeRepositoryProvider.overrideWithValue(repo),
      ]);
      final controller = container.read(barcodeControllerProvider.notifier);
      await controller.resolve('8901234567890');

      final result = await controller.saveFromScan(BarcodeSavePayload(
        barcode: '8901234567890',
        productMasterId: 101,
        price: 120,
        mrp: 150,
        quantity: 40,
        publish: true,
      ));

      expect(result, isNotNull);
      expect(repo.lastPayload!.price, 120);
      expect(repo.lastPayload!.quantity, 40);
      expect(repo.lastPayload!.publish, isTrue);
      expect(container.read(barcodeControllerProvider).status,
          BarcodeScanStatus.idle);
    });

                test('saveFromScan 409 conflict resets state and rethrows', () async {
      final repo = FakeBarcodeRepo(
        onSave: (_) async =>
            throw ApiException(statusCode: 409, message: 'Conflict'),
      );
      final container = makeContainer([
        barcodeRepositoryProvider.overrideWithValue(repo),
      ]);
      final controller = container.read(barcodeControllerProvider.notifier);
      await controller.resolve('8901234567890');

      Object? thrown;
      try {
        await controller.saveFromScan(BarcodeSavePayload(
          barcode: '8901234567890',
          productMasterId: 101,
          price: 120,
        ));
      } catch (e) {
        thrown = e;
      }
      expect(thrown, isA<ApiException>());
      final state = container.read(barcodeControllerProvider);
      expect(state.status, BarcodeScanStatus.error);
      expect(state.message, contains('Conflict'));
    });

    test('saveFromScan network failure lands in error state', () async {
      final repo = FakeBarcodeRepo(
        onSave: (_) async {
          throw ApiException(
            statusCode: 500, message: 'Internal server error');
        },
      );
      final container = makeContainer([
        barcodeRepositoryProvider.overrideWithValue(repo),
      ]);
      final controller = container.read(barcodeControllerProvider.notifier);
      await controller.resolve('8901234567890');

      Object? thrown;
      try {
        await controller.saveFromScan(BarcodeSavePayload(
          barcode: '8901234567890',
          productMasterId: 101,
          price: 120,
        ));
      } catch (e) {
        thrown = e;
      }
      expect(thrown, isA<ApiException>());
      final state = container.read(barcodeControllerProvider);
      expect(state.status, BarcodeScanStatus.error);
      expect(state.message, contains('Internal server error'));
    });

    test('reset returns controller to idle', () async {
      final container = makeContainer([
        barcodeRepositoryProvider.overrideWithValue(FakeBarcodeRepo()),
      ]);
      final controller = container.read(barcodeControllerProvider.notifier);
      await controller.resolve('8901234567890');
      expect(container.read(barcodeControllerProvider).status,
          BarcodeScanStatus.resolved);

      controller.reset();
      expect(container.read(barcodeControllerProvider).status,
          BarcodeScanStatus.idle);
    });
  });

  group('BarcodeConfirmSheet (req 26)', () {
    testWidgets('shows name, brand, barcode and image on the found product',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: tester.element(find.byType(ElevatedButton)),
                  isScrollControlled: true,
                  builder: (_) => BarcodeConfirmSheet(
                    resolution: const BarcodeResolution(
                      status: BarcodeResolutionStatus.found,
                      barcode: '8901234567890',
                      barcodeType: 'EAN-13',
                      matches: [
                        CatalogProductMatch(
                          productMasterId: 101,
                          name: 'Aashirvaad Salt 1kg',
                          brand: 'Aashirvaad',
                          imageUrl: 'https://example.com/salt.jpg',
                          isAvailableInCatalog: true,
                          matchType: 'IDENTIFIER',
                        ),
                      ],
                    ),
                    selectedMatch: const CatalogProductMatch(
                      productMasterId: 101,
                      name: 'Aashirvaad Salt 1kg',
                      brand: 'Aashirvaad',
                      imageUrl: 'https://example.com/salt.jpg',
                      isAvailableInCatalog: true,
                      matchType: 'IDENTIFIER',
                    ),
                    onSaved: () {},
                  ),
                ),
                child: const Text('show'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('show'));
      await tester.pumpAndSettle();

      expect(find.text('Aashirvaad Salt 1kg'), findsOneWidget);
      expect(find.text('Aashirvaad'), findsOneWidget);
      expect(find.text('Barcode 8901234567890 · EAN-13'), findsOneWidget);
      expect(find.text('Available in catalog'), findsOneWidget);
      expect(find.byType(CircleAvatar), findsOneWidget);
    });

    testWidgets('disables confirm when catalog unavailable', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: tester.element(find.byType(ElevatedButton)),
                  isScrollControlled: true,
                  builder: (_) => BarcodeConfirmSheet(
                    resolution: const BarcodeResolution(
                      status: BarcodeResolutionStatus.found,
                      barcode: '8901234567890',
                      matches: [
                        CatalogProductMatch(
                          productMasterId: 101,
                          name: 'Discontinued Item',
                          isAvailableInCatalog: false,
                          matchType: 'IDENTIFIER',
                        ),
                      ],
                    ),
                    selectedMatch: const CatalogProductMatch(
                      productMasterId: 101,
                      name: 'Discontinued Item',
                      isAvailableInCatalog: false,
                      matchType: 'IDENTIFIER',
                    ),
                    onSaved: () {},
                  ),
                ),
                child: const Text('show'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('show'));
      await tester.pumpAndSettle();

      expect(find.text('Currently unavailable in catalog'), findsOneWidget);
      final addBtn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Add to inventory'));
      expect(addBtn.enabled, isFalse);
    });

    testWidgets('renders normally when no image is present', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: tester.element(find.byType(ElevatedButton)),
                  isScrollControlled: true,
                  builder: (_) => BarcodeConfirmSheet(
                    resolution: const BarcodeResolution(
                      status: BarcodeResolutionStatus.found,
                      barcode: '8901234567890',
                      matches: [
                        CatalogProductMatch(
                          productMasterId: 1,
                          name: 'No Image Product',
                          isAvailableInCatalog: true,
                          matchType: 'IDENTIFIER',
                        ),
                      ],
                    ),
                    selectedMatch: const CatalogProductMatch(
                      productMasterId: 1,
                      name: 'No Image Product',
                      isAvailableInCatalog: true,
                      matchType: 'IDENTIFIER',
                    ),
                    onSaved: () {},
                  ),
                ),
                child: const Text('show'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('show'));
      await tester.pumpAndSettle();

      expect(find.text('No Image Product'), findsOneWidget);
      expect(find.byType(CircleAvatar), findsNothing);
    });
  });

  group('BarcodeManualEntrySheet (req 27 — manual add / retry path)', () {
    testWidgets('validates input and rejects non-numeric / wrong length',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: tester.element(find.byType(ElevatedButton)),
                  isScrollControlled: true,
                  builder: (_) => const BarcodeManualEntrySheet(),
                ),
                child: const Text('show'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('show'));
      await tester.pumpAndSettle();

      // Bad check digit → format validation error.
      await tester.enterText(
          find.byType(TextFormField), '8901234567891');
      await tester.tap(find.text('Look up'));
      await tester.pumpAndSettle();

      expect(find.text('Enter 8, 12, 13 or 14 digits'), findsOneWidget);
    });
  });
}
