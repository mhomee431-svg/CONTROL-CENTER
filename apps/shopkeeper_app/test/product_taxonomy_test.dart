import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/category_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/category_taxonomy.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_form_rules.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/controllers/category_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/widgets/product_sheets.dart';

import 'fakes.dart';

/// The manual form's taxonomy + barcode surface, driven by the REAL backend
/// contract: `/api/v1/categories` returns a FLAT list where a subcategory is
/// just a row with a `parent_id`, and `ShopkeeperProductCreate` treats all of
/// it as optional.

CategoryOption row(int id, String name,
        {int? parent, int sort = 0, bool active = true}) =>
    CategoryOption(
        id: id, name: name, parentId: parent, sortOrder: sort, isActive: active);

/// Grocery(1) → {Rice(11), Wheat(12)} and Pharmacy(2) → {Tablets(21)}.
/// Stationery(3) is deliberately leaf-only, so it must hide the subcategory
/// dropdown entirely.
List<CategoryOption> sampleTaxonomy() => [
      row(1, 'Grocery', sort: 1),
      row(11, 'Rice', parent: 1, sort: 2),
      row(12, 'Wheat', parent: 1, sort: 3),
      row(2, 'Pharmacy', sort: 4),
      row(21, 'Tablets', parent: 2, sort: 5),
      row(3, 'Stationery', sort: 6),
      // Inactive rows must never reach the picker.
      row(13, 'Discontinued', parent: 1, sort: 1, active: false),
      row(4, 'Archived', sort: 0, active: false),
    ];

ProviderContainer containerWith(FakeCategoryRepo repo) {
  final container = ProviderContainer(overrides: [
    categoryRepositoryProvider.overrideWithValue(repo),
    tokenStoreProvider.overrideWithValue(
        InMemoryTokenStore(accessToken: 'test-access-token')),
    selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('CategoryTaxonomy index', () {
    test('splits top level from children with one index build', () {
      final taxonomy = CategoryTaxonomy(sampleTaxonomy());
      expect(
        taxonomy.topLevel.map((c) => c.name).toList(),
        ['Grocery', 'Pharmacy', 'Stationery'],
      );
      expect(
        taxonomy.childrenOf(1).map((c) => c.name).toList(),
        ['Rice', 'Wheat'],
      );
      expect(taxonomy.childrenOf(2).map((c) => c.name).toList(), ['Tablets']);
    });

    test('a leaf-only category has NO children — the dropdown must hide', () {
      final taxonomy = CategoryTaxonomy(sampleTaxonomy());
      expect(taxonomy.childrenOf(3), isEmpty);
    });

    test('unknown and inactive ids resolve to nothing', () {
      final taxonomy = CategoryTaxonomy(sampleTaxonomy());
      expect(taxonomy.childrenOf(9999), isEmpty);
      expect(taxonomy.byId(13), isNull, reason: 'inactive rows are filtered');
      expect(taxonomy.byId(4), isNull, reason: 'inactive rows are filtered');
    });

    test('byId resolves live rows', () {
      final taxonomy = CategoryTaxonomy(sampleTaxonomy());
      expect(taxonomy.byId(11)?.name, 'Rice');
      expect(taxonomy.byId(null), isNull);
    });

    test('server ordering is preserved with a stable id tiebreak', () {
      final taxonomy = CategoryTaxonomy([
        row(2, 'B', sort: 5),
        row(1, 'A', sort: 5),
        row(3, 'C', sort: 1),
      ]);
      expect(taxonomy.topLevel.map((c) => c.name).toList(), ['C', 'A', 'B']);
    });

    test('an empty taxonomy is safe, not a crash', () {
      final taxonomy = CategoryTaxonomy(const []);
      expect(taxonomy.topLevel, isEmpty);
      expect(taxonomy.childrenOf(1), isEmpty);
    });
  });

  group('ProductFormRules.barcode', () {
    test('is optional — empty, blank or separators-only all pass', () {
      expect(ProductFormRules.barcode(''), isNull);
      expect(ProductFormRules.barcode(null), isNull);
      expect(ProductFormRules.barcode('   '), isNull);
      expect(ProductFormRules.barcode(' - - '), isNull);
    });

    test('normalises the same way the backend does before the length check',
        () {
      expect(
        ProductFormRules.normalizeBarcode(' 890-1234 5678 '),
        '89012345678',
      );
      // 8 real digits inside noisy text — valid once stripped.
      expect(ProductFormRules.barcode(' 12-34 5678 '), isNull);
    });

    test('rejects a barcode shorter than the backend minimum of 4', () {
      expect(
        ProductFormRules.barcode('123'),
        const ProductFormFieldFailure(ProductFormFieldError.barcodeTooShort,
            count: 4),
      );
    });

    test('allows non-digit codes rather than over-constraining', () {
      // The backend stores any string as a CUSTOM identifier.
      expect(ProductFormRules.barcode('AB-12'), isNull);
    });
  });

  group('CategoryController (one-shot cache)', () {
    test('fetches once and serves repeats from memory', () async {
      final repo = FakeCategoryRepo(rows: sampleTaxonomy());
      final container = containerWith(repo);

      final notifier = container.read(categoryControllerProvider.notifier);
      await notifier.ensureLoaded();
      await notifier.ensureLoaded();
      await notifier.ensureLoaded();

      expect(repo.calls, 1, reason: 'repeated sheet-opens must not re-fetch');
      final state = container.read(categoryControllerProvider);
      expect(state.status, CategoryLoadStatus.ready);
      expect(state.taxonomy!.topLevel, isNotEmpty);
    });

    test('a failure keeps the form usable and offers a retry', () async {
      final repo = FakeCategoryRepo(rows: sampleTaxonomy(), error: Exception('network down'));
      final container = containerWith(repo);

      await container.read(categoryControllerProvider.notifier).ensureLoaded();

      final state = container.read(categoryControllerProvider);
      expect(state.status, CategoryLoadStatus.error);
      expect(state.taxonomy, isNull);

      // A retry with a working repo resolves it.
      repo.error = null;
      await container.read(categoryControllerProvider.notifier).ensureLoaded();
      expect(
        container.read(categoryControllerProvider).status,
        CategoryLoadStatus.ready,
      );
    });
  });

  group('ProductCreateSheet taxonomy + barcode', () {
    Future<FakeProductRepo> openForm(
      WidgetTester tester,
      FakeCategoryRepo catRepo,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = FakeProductRepo();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          productRepositoryProvider.overrideWithValue(repo),
      inventoryRepositoryProvider.overrideWithValue(repo),
          categoryRepositoryProvider.overrideWithValue(catRepo),
          tokenStoreProvider.overrideWithValue(
              InMemoryTokenStore(accessToken: 'test-access-token')),
          selectedShopProvider
              .overrideWith(() => SelectedShopOverride(ownerShop())),
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

    Future<void> chooseDropdown(WidgetTester tester, Key key, String label) async {
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      // `.last` — the open overlay item, not the field's own text.
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    testWidgets('a leaf-only category hides the subcategory dropdown',
        (tester) async {
      await openForm(tester, FakeCategoryRepo(rows: sampleTaxonomy()));

      expect(find.byKey(const Key('create-category')), findsOneWidget);
      expect(find.byKey(const Key('create-subcategory')), findsNothing,
          reason: 'nothing chosen yet — an empty dropdown would be noise');

      await chooseDropdown(tester, const Key('create-category'), 'Stationery');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('create-subcategory')), findsNothing);
    });

    testWidgets('choosing a parent reveals its subcategories', (tester) async {
      await openForm(tester, FakeCategoryRepo(rows: sampleTaxonomy()));

      await chooseDropdown(tester, const Key('create-category'), 'Grocery');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('create-subcategory')), findsOneWidget);
    });

    testWidgets('category, subcategory and barcode reach the payload',
        (tester) async {
      final repo = await openForm(tester, FakeCategoryRepo(rows: sampleTaxonomy()));

      await tester.enterText(find.byType(TextFormField).at(0), 'Basmati Rice');
      await tester.enterText(find.byType(TextFormField).at(1), '120');

      await chooseDropdown(tester, const Key('create-category'), 'Grocery');
      await chooseDropdown(
          tester, const Key('create-subcategory'), 'Rice');

      await tester.tap(find.text('More details (optional)'));
      await tester.pumpAndSettle();
      // index 6 = SKU, 7 = barcode (both live under the expanded details).
      await tester.enterText(
          find.byType(TextFormField).at(7), ' 890-1234 5678 ');

      await tester.ensureVisible(find.text('Create product'));
      await tester.tap(find.text('Create product'));
      await tester.pumpAndSettle();

      final payload = repo.lastCreatePayload;
      expect(payload, isNotNull);
      expect(payload!['name'], 'Basmati Rice');
      // The barcode was normalised, not sent as pasted.
      expect(payload['barcode'], '89012345678');
      expect(payload['category_id'], 1);
      expect(payload['subcategory_id'], 11);
    });

    testWidgets('a taxonomy failure shows a retry and never blocks the form',
        (tester) async {
      final catRepo = FakeCategoryRepo(rows: sampleTaxonomy(), error: Exception('down'));
      final repo = await openForm(tester, catRepo);

      expect(find.textContaining('Could not load categories'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // The backend-required pair still works with no taxonomy at all.
      await tester.enterText(find.byType(TextFormField).at(0), 'Tea');
      await tester.enterText(find.byType(TextFormField).at(1), '50');
      await tester.ensureVisible(find.text('Create product'));
      await tester.tap(find.text('Create product'));
      await tester.pumpAndSettle();

      final payload = repo.lastCreatePayload;
      expect(payload, isNotNull);
      expect(payload!.containsKey('category_id'), isFalse);
      expect(payload.containsKey('subcategory_id'), isFalse);
      expect(payload.containsKey('barcode'), isFalse);
    });
  });
}
