import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/data/import_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/domain/import_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/presentation/controllers/import_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/presentation/screens/import_preview_screen.dart';

import 'package:go_router/go_router.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/presentation/screens/import_column_mapping_screen.dart';

import 'fakes.dart';

/// The Column Mapping step, end to end.
///
/// The panel is only worth having if it tells the truth about the file: which
/// column supplied which field, and what that field has to satisfy. Both halves
/// come from the backend — the server parses the header row, and the server owns
/// the rules — so these tests pin the two things the client could easily get
/// wrong: reading the server's mapping instead of inventing one, and rendering
/// the server's rules instead of restating them.

/// Always hands back the same workbook — the mapping panel is about what the
/// SERVER made of the file, so the pick itself only has to get out of the way.
class _AlwaysPicks implements WorkbookPickerService {
  const _AlwaysPicks();

  @override
  Future<PickedWorkbook?> pick() async =>
      const PickedWorkbook(path: '/tmp/stock.xlsx', name: 'stock.xlsx');
}

ProviderContainer _container({
  required FakeImportRepo repo,
  String? token = 'tok',
}) {
  final container = ProviderContainer(
    overrides: [
      inventoryImportRepositoryProvider.overrideWithValue(repo),
      workbookPickerProvider.overrideWithValue(const _AlwaysPicks()),
      tokenStoreProvider.overrideWithValue(
        InMemoryTokenStore(accessToken: token),
      ),
      selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// A sheet whose header row was read into four of the ten schema fields.
const Map<String, int> sheetMapping = {
  'product_name': 0,
  'brand': 1,
  'category': 2,
  'price': 4,
};

ImportPreview previewWith({Map<String, int> mapping = const {}}) =>
    ImportPreview(
      meta: const ImportJob(
        id: 42,
        filename: 'stock.xlsx',
        status: 'VALIDATED',
        totalRows: 3,
        validRows: 2,
        errorRows: 1,
      ),
      rows: const [
        ImportRow(rowNumber: 1, status: 'VALID', productName: 'Rice 5kg'),
        ImportRow(
          rowNumber: 2,
          status: 'ERROR',
          errorCode: 'UNKNOWN_CATEGORY',
          errorMessage: 'No category named "Snacks"',
        ),
      ],
      columnMapping: mapping,
    );

Future<ProviderContainer> uploadedPreview(FakeImportRepo repo) async {
  final container = _container(repo: repo);
  await container.read(importControllerProvider.notifier).pickAndUpload();
  return container;
}

Future<void> pumpPreview(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ImportPreviewScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openMappingPanel(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('import-column-mapping')));
  await tester.pumpAndSettle();
}

void main() {
  group('The upload tells the client how the header row was read', () {
    test('column_mapping is parsed instead of dropped', () {
      final preview = ImportPreview.fromJson(const {
        'id': 7,
        'filename': 's.xlsx',
        'status': 'AWAITING_CONFIRMATION',
        'total_rows': 2,
        'valid_rows': 2,
        'error_rows': 0,
        'column_mapping': {'barcode': 0, 'price': 5},
      });

      expect(preview.columnMapping, {'barcode': 0, 'price': 5});
    });

    test('a payload without column_mapping is empty, not an error', () {
      final preview = ImportPreview.fromJson(const {
        'id': 7,
        'filename': 's.xlsx',
        'status': 'AWAITING_CONFIRMATION',
        'total_rows': 1,
        'valid_rows': 1,
        'error_rows': 0,
      });

      expect(preview.columnMapping, isEmpty);
    });

    test('an unreadable column index does not discard the mapping', () {
      final preview = ImportPreview.fromJson(const {
        'id': 7,
        'filename': 's.xlsx',
        'status': 'AWAITING_CONFIRMATION',
        'total_rows': 1,
        'valid_rows': 1,
        'error_rows': 0,
        'column_mapping': {'barcode': 0, 'price': null},
      });

      expect(preview.columnMapping, {'barcode': 0, 'price': -1});
    });
  });

  group('The import schema is read, not restated', () {
    test('fields keep their server order, aliases and rules', () {
      final schema = ImportSchema.fromJson(const {
        'fields': [
          {
            'name': 'category',
            'label': 'Category',
            'aliases': ['dept', 'department'],
            'rules': ['Must match an existing top-level category'],
            'required': false,
            'in_sample': true,
          },
          {
            'name': 'price',
            'label': 'Price',
            'aliases': [],
            'rules': ['Required', 'Number >= 0'],
            'required': true,
            'in_sample': true,
          },
        ],
        'required_any_of': ['Barcode', 'SKU', 'Product Name'],
      });

      expect(schema.fields.map((f) => f.name), ['category', 'price']);
      expect(schema.fields.first.aliases, ['dept', 'department']);
      expect(schema.fields.last.rules, ['Required', 'Number >= 0']);
      expect(schema.fields.last.isRequired, isTrue);
      expect(schema.requiredAnyOf, ['Barcode', 'SKU', 'Product Name']);
    });

    test('a field with no aliases or rules tolerates their absence', () {
      final schema = ImportSchema.fromJson(const {
        'fields': [
          {'name': 'availability', 'label': 'Availability'},
        ],
      });

      expect(schema.fields.single.aliases, isEmpty);
      expect(schema.fields.single.rules, isEmpty);
      expect(schema.fields.single.inSample, isTrue);
    });

    test('column positions are named the way a spreadsheet names them', () {
      const field = ImportSchemaField(name: 'price', label: 'Price', rules: []);

      expect(field.columnLabel({'price': 0}), 'Column A');
      expect(field.columnLabel({'price': 4}), 'Column E');
      expect(field.columnLabel({'price': 25}), 'Column Z');
      expect(field.columnLabel({'price': 26}), 'Column AA');
    });

    test('a field the file lacks has no column, not a wrong one', () {
      const field = ImportSchemaField(name: 'mrp', label: 'MRP', rules: []);

      expect(field.columnLabel({'price': 0}), isNull);
      expect(field.mappedIn({'price': 0}), isFalse);
    });
  });

  group('Schema loading', () {
    test('is fetched once and then reused', () async {
      final repo = FakeImportRepo();
      final container = _container(repo: repo);
      final notifier = container.read(importControllerProvider.notifier);

      await notifier.loadSchema();
      await notifier.loadSchema();

      expect(repo.schemaCalls, 1);
      expect(container.read(importControllerProvider).schema, isNotNull);
    });

    test('a failing schema never becomes an import error', () async {
      final repo = FakeImportRepo(
        schemaError: ApiException(statusCode: 500, message: 'down'),
      );
      final container = _container(repo: repo);

      await container.read(importControllerProvider.notifier).loadSchema();

      final state = container.read(importControllerProvider);
      expect(state.schema, isNull);
      expect(state.status, ImportStatus.idle);
      expect(state.message, isNull);
    });

    test('no access token means no request', () async {
      final repo = FakeImportRepo();
      final container = _container(repo: repo, token: null);

      await container.read(importControllerProvider.notifier).loadSchema();

      expect(repo.schemaCalls, 0);
    });

    test('the schema survives a step of the import flow', () async {
      final repo = FakeImportRepo(onUpload: previewWith(mapping: sheetMapping));
      final container = _container(repo: repo);
      final notifier = container.read(importControllerProvider.notifier);

      await notifier.loadSchema();
      await notifier.pickAndUpload();

      final state = container.read(importControllerProvider);
      expect(state.status, ImportStatus.preview);
      expect(state.schema, isNotNull);
    });
  });

  group('Column Mapping panel', () {
    testWidgets('summarises how many columns were recognised', (tester) async {
      final repo = FakeImportRepo(onUpload: previewWith(mapping: sheetMapping));
      await pumpPreview(tester, await uploadedPreview(repo));

      expect(find.byKey(const Key('import-column-mapping')), findsOneWidget);
      // 4 of the schema's 10 fields were present in this sheet.
      expect(find.text('4 of 10'), findsOneWidget);
    });

    testWidgets('renders each field\'s column, aliases and rules', (
      tester,
    ) async {
      final repo = FakeImportRepo(onUpload: previewWith(mapping: sheetMapping));
      await pumpPreview(tester, await uploadedPreview(repo));
      await openMappingPanel(tester);

      // Category is at index 2, so it is column C.
      expect(
        find.byKey(const Key('import-mapping-column-category')),
        findsOneWidget,
      );
      expect(find.text('Column C'), findsOneWidget);
      // The alias list and rule text come from the schema payload, not the app.
      expect(find.text('Also accepts: dept, department'), findsOneWidget);
      expect(
        find.text('Must match an existing top-level category'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('import-mapping-column-price')), findsOneWidget);
      expect(find.text('Column E'), findsOneWidget);
    });

    testWidgets('says a schema field is missing from this file', (tester) async {
      final repo = FakeImportRepo(onUpload: previewWith(mapping: sheetMapping));
      await pumpPreview(tester, await uploadedPreview(repo));
      await openMappingPanel(tester);

      expect(
        find.byKey(const Key('import-mapping-column-mrp')),
        findsOneWidget,
      );
      expect(find.text('Not in this file'), findsNWidgets(6));
    });

    testWidgets('falls back to the raw mapping when the schema is down', (
      tester,
    ) async {
      final repo = FakeImportRepo(
        onUpload: previewWith(mapping: sheetMapping),
        schemaError: ApiException(statusCode: 500, message: 'down'),
      );
      await pumpPreview(tester, await uploadedPreview(repo));
      await openMappingPanel(tester);

      // It admits the rules are missing rather than inventing a field list…
      expect(find.byKey(const Key('import-mapping-noschema')), findsOneWidget);
      // …and lists only the columns this upload actually read.
      expect(find.text('4 of 4'), findsOneWidget);
      expect(find.text('Category'), findsOneWidget);
      expect(
        find.text('Must match an existing top-level category'),
        findsNothing,
      );
    });

    testWidgets('stays hidden when the payload carries no mapping', (
      tester,
    ) async {
      final repo = FakeImportRepo(onUpload: previewWith());
      await pumpPreview(tester, await uploadedPreview(repo));

      expect(find.byKey(const Key('import-column-mapping')), findsNothing);
      // The flow itself is untouched by the mapping panel.
      expect(find.byKey(const Key('import-confirm')), findsOneWidget);
    });
  });
  group('Reading the column proposal', () {
    test('a contested column arrives unmapped, with its reason', () {
      final preview = ImportPreview.fromJson(const {
        'id': 42,
        'filename': 's.xlsx',
        'status': 'AWAITING_CONFIRMATION',
        'total_rows': 1,
        'valid_rows': 0,
        'error_rows': 1,
        'header_row': ['Barcode', 'Price', 'Selling Price'],
        'column_mapping': {'barcode': 0},
        'column_proposal': [
          {
            'column_index': 0,
            'header': 'Barcode',
            'suggested_field': 'barcode',
            'status': 'matched',
          },
          {
            'column_index': 1,
            'header': 'Price',
            'candidates': ['price'],
            'status': 'ambiguous',
            'reason': 'MULTIPLE_COLUMNS_CLAIM_THIS_FIELD',
          },
          {
            'column_index': 2,
            'header': 'Selling Price',
            'candidates': ['price'],
            'status': 'ambiguous',
            'reason': 'MULTIPLE_COLUMNS_CLAIM_THIS_FIELD',
          },
        ],
      });

      expect(preview.headerRow, ['Barcode', 'Price', 'Selling Price']);
      expect(preview.ambiguousColumns.map((c) => c.header), [
        'Price',
        'Selling Price',
      ]);
      for (final column in preview.ambiguousColumns) {
        expect(column.suggestedField, isNull);
        expect(column.ambiguityReason, isNotEmpty);
      }
    });

    test('an ambiguous column explains WHICH choice is contested', () {
      // "We did not map it" on its own is not actionable.
      expect(
        const ImportColumnProposal(
          columnIndex: 2,
          header: 'Selling Price',
          status: 'ambiguous',
          reason: ImportColumnProposal.reasonDuplicateColumn,
        ).ambiguityReason,
        contains('Another column'),
      );
      expect(
        const ImportColumnProposal(
          columnIndex: 2,
          header: 'Code',
          status: 'ambiguous',
          reason: ImportColumnProposal.reasonSeveralFields,
        ).ambiguityReason,
        contains('more than one field'),
      );
    });

    test('the screen is seeded from the APPLIED mapping, not the suggestions',
        () {
      // Otherwise reopening the step would undo a correction the shopkeeper
      // already made, by re-proposing the guess they rejected.
      final preview = contestedPreview(
        applied: {'barcode': 0, 'product_name': 1, 'price': 3},
      );

      final assignment = preview.initialAssignment();
      expect(assignment[0], 'barcode');
      expect(assignment[1], 'product_name');
      expect(assignment[3], 'price');
      expect(assignment[2], isNull);
    });

    test('columns are addressed by their spreadsheet position', () {
      expect(
        const ImportColumnProposal(
          columnIndex: 2,
          header: 'Price',
          status: 'ambiguous',
        ).columnLetter,
        'C',
      );
      expect(
        const ImportColumnProposal(columnIndex: 26, header: 'x').columnLetter,
        'AA',
      );
    });
  });

  group('Submitting a correction', () {
    test('the draft is sent field-keyed, as the API takes it', () async {
      final repo = FakeImportRepo(onUpload: contestedPreview());
      final container = await stagedContested(repo);

      final ok = await container
          .read(importControllerProvider.notifier)
          .remapColumns({0: 'barcode', 1: 'product_name', 2: 'price', 3: null});

      expect(ok, isTrue);
      expect(repo.remapCalls, 1);
      expect(repo.remappedJobIds, [42]);
      expect(repo.remappedMappings.single, {
        'barcode': 0,
        'product_name': 1,
        'price': 2,
      });
    });

    test('a column left unassigned is omitted, not sent as null', () async {
      final repo = FakeImportRepo(onUpload: contestedPreview());
      final container = await stagedContested(repo);

      await container
          .read(importControllerProvider.notifier)
          .remapColumns({0: 'barcode', 1: 'product_name', 2: 'price', 3: null});

      expect(repo.remappedMappings.single.length, 3);
      expect(repo.remappedMappings.single.containsKey('mrp'), isFalse);
    });

    test('the preview is REPLACED, because the rows changed', () async {
      final repo = FakeImportRepo(
        onUpload: contestedPreview(),
        remapResult: ImportPreview(
          meta: const ImportJob(
            id: 42,
            filename: 'stock.xlsx',
            status: 'AWAITING_CONFIRMATION',
            totalRows: 3,
            validRows: 3,
            errorRows: 0,
          ),
          columnMapping: const {'barcode': 0, 'product_name': 1, 'price': 2},
        ),
      );
      final container = await stagedContested(repo);
      expect(container.read(importControllerProvider).preview!.validCount, 0);

      await container
          .read(importControllerProvider.notifier)
          .remapColumns({0: 'barcode', 1: 'product_name', 2: 'price'});

      final state = container.read(importControllerProvider);
      expect(state.preview!.validCount, 3);
      expect(state.preview!.columnMapping['price'], 2);
    });

    test('a rejected mapping leaves the import in review, not failed', () async {
      final repo = FakeImportRepo(
        onUpload: contestedPreview(),
        remapError: ApiException(
          statusCode: 400,
          message: 'this file only has 4 columns',
        ),
      );
      final container = await stagedContested(repo);

      final ok = await container
          .read(importControllerProvider.notifier)
          .remapColumns({0: 'barcode', 99: 'price'});

      final state = container.read(importControllerProvider);
      expect(ok, isFalse);
      // Nothing was applied, so the review the shopkeeper was doing survives.
      expect(state.status, ImportStatus.preview);
      expect(state.message, isNull);
      expect(state.mappingError, contains('only has 4 columns'));
      expect(state.remapping, isFalse);
    });
  });

  group('The mapping screen', () {
    testWidgets('lists the shopkeepers own column headings', (tester) async {
      final container = await stagedContested(
        FakeImportRepo(onUpload: contestedPreview()),
      );

      await pumpMappingScreen(tester, container);

      for (final (index, heading) in [
        (0, 'Barcode'),
        (1, 'Item Name'),
        (2, 'Price'),
        (3, 'Selling Price'),
      ]) {
        // Read the keyed Text directly: a mapped column's label ALSO renders as
        // the dropdown's selected item, so a bare find.text would match twice
        // and a descendant search would match nothing (Text is the leaf).
        expect(
          tester.widget<Text>(find.byKey(Key('import-map-header-$index'))).data,
          heading,
          reason: 'column $index should show the heading as written in the file',
        );
        // One dropdown per column, addressed by spreadsheet position.
        expect(find.byKey(Key('import-map-field-$index')), findsOneWidget);
      }
      expect(find.text('Column D'), findsOneWidget);
    });

    testWidgets('says which columns it refused to guess at', (tester) async {
      final container = await stagedContested(
        FakeImportRepo(onUpload: contestedPreview()),
      );

      await pumpMappingScreen(tester, container);

      expect(find.byKey(const Key('import-map-warning')), findsOneWidget);
      expect(
        find.textContaining('2 columns need your choice'),
        findsOneWidget,
      );
      // Both contested columns explain themselves, individually.
      expect(
        find.byKey(const Key('import-map-reason-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('import-map-reason-3')),
        findsOneWidget,
      );
    });

    testWidgets('an already-resolved column raises no warning', (tester) async {
      final container = await stagedContested(
        FakeImportRepo(
          onUpload: contestedPreview(
            applied: {'barcode': 0, 'product_name': 1, 'price': 2},
          ),
        ),
      );

      await pumpMappingScreen(tester, container);

      expect(find.byKey(const Key('import-map-warning')), findsNothing);
      expect(
        find.byKey(Key('import-map-save')),
        findsOneWidget,
      );
    });

    testWidgets('saving is blocked while a contested column is undecided',
        (tester) async {
      final container = await stagedContested(
        FakeImportRepo(onUpload: contestedPreview()),
      );

      await pumpMappingScreen(tester, container);

      final save = tester.widget<FilledButton>(
        find.byKey(const Key('import-map-save')),
      );
      expect(save.onPressed, isNull);
    });

    testWidgets('choosing a field submits exactly that mapping', (tester) async {
      final repo = FakeImportRepo(onUpload: contestedPreview());
      useTallSurface(tester);
      final container = await stagedContested(repo);

      await pumpMappingScreen(tester, container);

      // The shopkeeper says "Selling Price" is the price, not "Price".
      // Scroll it into view first: the last row of a list is often below the
      // fold, and tapping an off-screen widget silently hits nothing.
      await tester.ensureVisible(find.byKey(const Key('import-map-field-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-map-field-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Price').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import-map-save')));
      await tester.pumpAndSettle();

      expect(repo.remapCalls, 1);
      expect(repo.remappedMappings.single, {
        'barcode': 0,
        'product_name': 1,
        'price': 3,
      });
      // "Price" itself was left as Don't import, so it is not in the payload.
      expect(repo.remappedMappings.single.containsKey('mrp'), isFalse);
    });

    testWidgets('a rejected mapping is shown without losing the draft',
        (tester) async {
      final repo = FakeImportRepo(
        onUpload: contestedPreview(),
        remapError: ApiException(
          statusCode: 400,
          message: 'this file only has 4 columns',
        ),
      );
      useTallSurface(tester);
      final container = await stagedContested(repo);

      await pumpMappingScreen(tester, container);
      await tester.ensureVisible(find.byKey(const Key('import-map-field-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-map-field-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Price').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-map-save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('import-map-error')), findsOneWidget);
      // Still on the mapping screen — the import was not thrown away.
      expect(find.byKey(const Key('import-map-save')), findsOneWidget);
    });
  });

}

/// A sheet with the classic contested pair: "Price" AND "Selling Price".
///
/// The backend refuses to choose between them, so both arrive unmapped and the
/// shopkeeper must — which is exactly what the correction step is for.
ImportPreview contestedPreview({
  Map<String, int> applied = const {'barcode': 0, 'product_name': 1},
}) =>
    ImportPreview(
      meta: const ImportJob(
        id: 42,
        filename: 'stock.xlsx',
        status: 'AWAITING_CONFIRMATION',
        totalRows: 3,
        validRows: 0,
        errorRows: 3,
      ),
      columnMapping: applied,
      headerRow: const ['Barcode', 'Item Name', 'Price', 'Selling Price'],
      columnProposal: const [
        ImportColumnProposal(
          columnIndex: 0,
          header: 'Barcode',
          suggestedField: 'barcode',
          status: 'matched',
        ),
        ImportColumnProposal(
          columnIndex: 1,
          header: 'Item Name',
          suggestedField: 'product_name',
          status: 'matched',
        ),
        ImportColumnProposal(
          columnIndex: 2,
          header: 'Price',
          candidates: ['price'],
          status: 'ambiguous',
          reason: ImportColumnProposal.reasonDuplicateColumn,
        ),
        ImportColumnProposal(
          columnIndex: 3,
          header: 'Selling Price',
          candidates: ['price'],
          status: 'ambiguous',
          reason: ImportColumnProposal.reasonDuplicateColumn,
        ),
      ],
    );

/// Pump the mapping screen ON TOP of the preview, as the app does it.
///
/// Pushed rather than placed at the initial location because a successful save
/// pops: with only one route on the stack, `context.pop()` throws "there is
/// nothing to pop" and the test would blame the screen for a routing setup the
/// real app never has.
Future<void> pumpMappingScreen(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final router = GoRouter(
    initialLocation: '/import-preview',
    routes: [
      GoRoute(path: '/import-preview', builder: (_, _) => const Scaffold()),
      GoRoute(
        path: '/import-column-mapping',
        builder: (_, _) => const ImportColumnMappingScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  router.push('/import-column-mapping');
  await tester.pumpAndSettle();
}

/// Gives the test a tall surface so an OPEN dropdown menu -- which renders in
/// an overlay route -- is fully on screen and therefore actually tappable.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<ProviderContainer> stagedContested(FakeImportRepo repo) async {
  final container = _container(repo: repo);
  final notifier = container.read(importControllerProvider.notifier);
  await notifier.loadSchema();
  await notifier.pickAndUpload();
  return container;
}

