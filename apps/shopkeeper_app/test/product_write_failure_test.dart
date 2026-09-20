import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/category_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/widgets/product_sheets.dart';

import 'fakes.dart';

/// A REJECTED product write must never close the sheet.
///
/// Closing it would destroy every typed field — the shopkeeper's actual work —
/// and leave only a transient SnackBar behind. That is precisely the
/// "never silently lose a user update" rule the offline specification calls
/// out, and it is the behaviour `update_price_screen.dart`, `stock_sheets.dart`
/// and `offer_create_sheet.dart` already follow.
///
/// These tests pin the two sheets that did NOT: the edit sheet and the manual
/// create sheet.
void main() {
  /// The exact sentence the backend/transport produced. It must reach the
  /// screen verbatim — never a generic "Update failed".
  const offlineMessage =
      "You're offline — changes can't be saved until you're back online.";

  ShopProductItem milk() => const ShopProductItem(
        id: 11,
        name: 'Amul Milk 1L',
        status: 'ACTIVE',
        price: 27,
        mrp: 30,
        isActive: true,
        isAvailable: true,
        quantity: 5,
        stockStatus: 'LOW_STOCK',
      );

  Widget host(Widget sheet) => MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => sheet,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  Future<void> pumpHost(
    WidgetTester tester,
    Widget sheet,
    FakeProductRepo repo,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        productRepositoryProvider.overrideWithValue(repo),
      inventoryRepositoryProvider.overrideWithValue(repo),
        // The create sheet resolves the taxonomy on open — never hit the wire.
        categoryRepositoryProvider.overrideWithValue(FakeCategoryRepo()),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider
            .overrideWith(() => SelectedShopOverride(ownerShop(id: 10))),
      ],
      child: host(sheet),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }


  group('ProductCreateSheet — a rejected create keeps the form', () {
    testWidgets('stays open, reports the reason and preserves every value',
        (tester) async {
      final repo = FakeProductRepo(
        onCreate: (_) => throw const ApiException(message: offlineMessage),
      );
      await pumpHost(tester, const ProductCreateSheet(), repo);

      await tester.enterText(find.byType(TextFormField).at(0), 'Basmati Rice');
      await tester.enterText(find.byType(TextFormField).at(1), '120');
      await tester.tap(find.text('Create product'));
      await tester.pumpAndSettle();

      // 1. The sheet did NOT close — the work is still on screen.
      expect(find.byType(ProductCreateSheet), findsOneWidget);
      expect(find.text('Create product'), findsOneWidget);

      // 2. The failure is reported inline, in the backend's own words.
      expect(find.byKey(const Key('product-create-error')), findsOneWidget);
      expect(find.text(offlineMessage), findsOneWidget);

      // 3. The typed values survived, so a retry needs no retyping.
      expect(find.text('Basmati Rice'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
    });

    testWidgets('an accepted create closes the sheet', (tester) async {
      final repo = FakeProductRepo();
      await pumpHost(tester, const ProductCreateSheet(), repo);

      await tester.enterText(find.byType(TextFormField).at(0), 'Basmati Rice');
      await tester.enterText(find.byType(TextFormField).at(1), '120');
      await tester.tap(find.text('Create product'));
      await tester.pumpAndSettle();

      expect(find.byType(ProductCreateSheet), findsNothing);
      expect(repo.lastCreatePayload?['name'], 'Basmati Rice');
    });
  });

  group('ProductEditSheet — a rejected edit keeps the form', () {
    testWidgets('stays open, reports the reason and preserves every value',
        (tester) async {
      final repo = FakeProductRepo(
        onUpdate: (_, _) => throw const ApiException(message: offlineMessage),
      );
      await pumpHost(tester, ProductEditSheet(item: milk()), repo);

      await tester.enterText(find.byType(TextFormField).at(0), '99');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(find.byType(ProductEditSheet), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);
      expect(find.byKey(const Key('product-edit-error')), findsOneWidget);
      expect(find.text(offlineMessage), findsOneWidget);
      expect(find.text('99'), findsOneWidget);
    });

    testWidgets('an accepted edit closes the sheet', (tester) async {
      final repo = FakeProductRepo();
      await pumpHost(tester, ProductEditSheet(item: milk()), repo);

      await tester.enterText(find.byType(TextFormField).at(0), '99');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(find.byType(ProductEditSheet), findsNothing);
      expect(repo.lastUpdateFields?['price'], 99);
    });

    testWidgets('a rejected edit is never announced as saved', (tester) async {
      final repo = FakeProductRepo(
        onUpdate: (_, _) => throw const ApiException(message: offlineMessage),
      );
      await pumpHost(tester, ProductEditSheet(item: milk()), repo);

      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      // The success SnackBar is the app claiming a write landed. It must not
      // appear when the backend refused the change.
      expect(find.text('Product updated'), findsNothing);
      expect(repo.lastUpdateFields, isNotNull);
    });
  });
}

