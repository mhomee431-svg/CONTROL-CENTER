import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/category_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_form_rules.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/widgets/product_sheets.dart';

import 'fakes.dart';

/// The manual product form must ask for EXACTLY what the backend requires.
///
/// Backend authority: `ShopkeeperProductCreate` (schemas/shopkeeper.py)
/// requires only `name` and `price`; every other field is optional and every
/// numeric field is bounded at `>= 0`. `shopkeeper_service` additionally
/// rejects `mrp < price`. These tests pin that contract on the client side —
/// both that the optional fields stay optional, and that the constraints the
/// backend enforces are caught before the round trip.
void main() {
  group('ProductFormRules.name (required)', () {
    test('rejects empty and whitespace-only', () {
      expect(ProductFormRules.name(null),
          const ProductFormFieldFailure(ProductFormFieldError.nameRequired));
      expect(ProductFormRules.name(''),
          const ProductFormFieldFailure(ProductFormFieldError.nameRequired));
      expect(
        ProductFormRules.name('   '),
        const ProductFormFieldFailure(ProductFormFieldError.nameRequired),
      );
    });

    test('accepts a normal name', () {
      expect(ProductFormRules.name('Paracetamol 500mg'), isNull);
    });

    test('caps at the backend max of 255 characters', () {
      expect(ProductFormRules.name('a' * 255), isNull);
      expect(
        ProductFormRules.name('a' * 256),
        const ProductFormFieldFailure(
            ProductFormFieldError.tooManyCharacters, count: 255),
      );
    });
  });

  group('ProductFormRules.price (required, >= 0)', () {
    test('is required', () {
      expect(ProductFormRules.price(''),
          const ProductFormFieldFailure(ProductFormFieldError.priceRequired));
      expect(ProductFormRules.price(null),
          const ProductFormFieldFailure(ProductFormFieldError.priceRequired));
    });

    test('rejects non-numeric input', () {
      expect(ProductFormRules.price('abc'),
          const ProductFormFieldFailure(ProductFormFieldError.invalidAmount));
    });

    test('rejects negatives — the backend bounds this at ge=0', () {
      expect(ProductFormRules.price('-1'),
          const ProductFormFieldFailure(ProductFormFieldError.priceNegative));
      expect(ProductFormRules.price('-0.01'),
          const ProductFormFieldFailure(ProductFormFieldError.priceNegative));
    });

    test('zero and decimals are valid', () {
      expect(ProductFormRules.price('0'), isNull);
      expect(ProductFormRules.price('149.99'), isNull);
    });
  });

  group('ProductFormRules.mrp (optional)', () {
    test('an empty MRP is allowed — never mandatory', () {
      expect(ProductFormRules.mrp('', priceText: '100'), isNull);
      expect(ProductFormRules.mrp(null, priceText: '100'), isNull);
      expect(ProductFormRules.mrp('  ', priceText: '100'), isNull);
    });

    test('rejects non-numeric and negative values', () {
      expect(
        ProductFormRules.mrp('abc', priceText: '100'),
        const ProductFormFieldFailure(ProductFormFieldError.invalidAmount),
      );
      expect(
        ProductFormRules.mrp('-5', priceText: '100'),
        const ProductFormFieldFailure(ProductFormFieldError.mrpNegative),
      );
    });

    test('mirrors the backend rule: MRP may not undercut the price', () {
      expect(
        ProductFormRules.mrp('90', priceText: '100'),
        const ProductFormFieldFailure(ProductFormFieldError.mrpBelowPrice),
      );
      // Equal is allowed (the backend only rejects strictly lower).
      expect(ProductFormRules.mrp('100', priceText: '100'), isNull);
      expect(ProductFormRules.mrp('120', priceText: '100'), isNull);
    });

    test('skips the cross-field check while the price is unusable', () {
      expect(ProductFormRules.mrp('90', priceText: ''), isNull);
      expect(ProductFormRules.mrp('90', priceText: 'abc'), isNull);
    });
  });

  group('ProductFormRules.quantity (optional)', () {
    test('an empty quantity is allowed — never mandatory', () {
      expect(ProductFormRules.quantity(''), isNull);
      expect(ProductFormRules.quantity(null), isNull);
    });

    test('rejects fractions and negatives', () {
      expect(ProductFormRules.quantity('2.5'),
          const ProductFormFieldFailure(
              ProductFormFieldError.wholeNumberRequired));
      expect(ProductFormRules.quantity('-3'),
          const ProductFormFieldFailure(
              ProductFormFieldError.quantityNegative));
    });

    test('zero and whole numbers are valid', () {
      expect(ProductFormRules.quantity('0'), isNull);
      expect(ProductFormRules.quantity('48'), isNull);
    });
  });

  group('ProductFormRules.optionalMax', () {
    test('empty is allowed for every optional field', () {
      expect(ProductFormRules.optionalMax('', 120), isNull);
      expect(ProductFormRules.optionalMax(null, 50), isNull);
    });

    test('enforces the backend maximum length', () {
      expect(ProductFormRules.optionalMax('a' * 120, 120), isNull);
      expect(
        ProductFormRules.optionalMax('a' * 121, 120),
        const ProductFormFieldFailure(
            ProductFormFieldError.tooManyCharacters, count: 120),
      );
    });

    test('the declared maxima match the backend schema', () {
      expect(ProductFormRules.nameMaxLength, 255);
      expect(ProductFormRules.brandMaxLength, 120);
      expect(ProductFormRules.unitMaxLength, 50);
      expect(ProductFormRules.skuMaxLength, 100);
    });
  });

  group('ProductCreateSheet (manual entry)', () {
    /// Opens the real create sheet over a modal, exactly like the app does,
    /// with only the repository faked.
    Future<FakeProductRepo> openForm(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = FakeProductRepo();
      // The create sheet resolves the taxonomy on open — never hit the network.
      final categoryRepo = FakeCategoryRepo();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          productRepositoryProvider.overrideWithValue(repo),
      inventoryRepositoryProvider.overrideWithValue(repo),
          categoryRepositoryProvider.overrideWithValue(categoryRepo),
          tokenStoreProvider.overrideWithValue(
              InMemoryTokenStore(accessToken: 'test-access-token')),
          selectedShopProvider
              .overrideWith(() => SelectedShopOverride(ownerShop(id: 10))),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const ProductCreateSheet(),
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
      return repo;
    }

    Future<void> submit(WidgetTester tester) async {
      await tester.tap(find.text('Create product'));
      await tester.pumpAndSettle();
    }

    testWidgets('only name and price are marked mandatory', (tester) async {
      await openForm(tester);

      expect(find.text('Product name *'), findsOneWidget);
      expect(find.text('Selling price *'), findsOneWidget);
      // Everything else is explicitly optional.
      expect(find.text('Brand (optional)'), findsOneWidget);
      expect(find.text('More details (optional)'), findsOneWidget);
    });

    testWidgets('an empty form blocks on the two required fields only',
        (tester) async {
      final repo = await openForm(tester);
      await submit(tester);

      expect(find.text('Product name is required'), findsOneWidget);
      expect(find.text('Selling price is required'), findsOneWidget);
      expect(repo.lastCreatePayload, isNull);
    });

    testWidgets('name + price alone create a product — optionals stay optional',
        (tester) async {
      final repo = await openForm(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'Basmati Rice');
      await tester.enterText(find.byType(TextFormField).at(1), '120');
      await submit(tester);

      // The backend-required pair was enough; nothing else was demanded.
      expect(repo.lastCreatePayload, isNotNull);
      expect(repo.lastCreatePayload!['name'], 'Basmati Rice');
      expect(repo.lastCreatePayload!['price'], 120);
      // Untouched optionals are omitted rather than sent as empty strings.
      expect(repo.lastCreatePayload!.containsKey('brand_name'), isFalse);
      expect(repo.lastCreatePayload!.containsKey('sku'), isFalse);
      expect(repo.lastCreatePayload!.containsKey('unit'), isFalse);
      expect(repo.lastCreatePayload!.containsKey('description'), isFalse);
    });

    testWidgets('a negative price is blocked before the round trip',
        (tester) async {
      final repo = await openForm(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'Sugar');
      await tester.enterText(find.byType(TextFormField).at(1), '-5');
      await submit(tester);

      expect(find.text('Price cannot be negative'), findsOneWidget);
      expect(repo.lastCreatePayload, isNull);
    });

    testWidgets('an MRP below the selling price is blocked', (tester) async {
      final repo = await openForm(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'Tea');
      await tester.enterText(find.byType(TextFormField).at(1), '200');
      await tester.enterText(find.byType(TextFormField).at(2), '150');
      await submit(tester);

      expect(
        find.text('MRP cannot be lower than the selling price'),
        findsOneWidget,
      );
      expect(repo.lastCreatePayload, isNull);
    });
  });
}
