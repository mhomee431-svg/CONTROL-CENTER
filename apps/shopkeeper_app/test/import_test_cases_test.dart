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

import 'fakes.dart';

/// Fake picker that returns a canned workbook or cancels (no platform channel).
class FakePicker implements WorkbookPickerService {
  FakePicker({this.workbook, this.shouldCancel = false});

  PickedWorkbook? workbook;
  bool shouldCancel;
  int calls = 0;

  @override
  Future<PickedWorkbook?> pick() async {
    calls++;
    if (shouldCancel) return null;
    return workbook ?? const PickedWorkbook(path: '/tmp/a.xlsx', name: 'a.xlsx');
  }
}

/// Spec §133 IMPORT TEST CASES: valid file, invalid file, cancelled picker,
/// empty file, large file, duplicate barcode, invalid category, invalid price,
/// partial success, server failure, retry.
///
/// Most of the file-level cases are enforced by the backend
/// (`upload_security.validate_upload` rejects a wrong extension, a non-.xlsx
/// magic header and an EMPTY_FILE; the 10 MB body cap lives in the security
/// middleware) and the app's job is to surface those reasons readably rather
/// than flattening them into "Upload failed".
///
/// The row-level cases arrive as backend error codes. The two that were being
/// LOST on the way in are covered here: `error_field` (the "Field" column §42
/// requires) and `idempotent_replay` (which silently handed the shopkeeper a
/// previous job's rows).
void main() {
  ImportJob job({
    int id = 7,
    String filename = 'stock.xlsx',
    String status = 'VALIDATED',
    int total = 4,
    int valid = 2,
    int errors = 2,
    int processed = 0,
    int failed = 0,
  }) =>
      ImportJob(
        id: id,
        filename: filename,
        status: status,
        totalRows: total,
        validRows: valid,
        errorRows: errors,
        processedRows: processed,
        failedRows: failed,
        createdAt: DateTime(2026, 2, 1),
      );

  /// One preview row exactly as `_preview_row` sends it.
  Map<String, dynamic> rowJson(
    int n, {
    String status = 'VALID',
    String? code,
    String? field,
    String? message,
    String? name,
  }) =>
      {
        'row_number': n,
        'status': status,
        'product_name': name,
        'error_code': code,
        'error_field': field,
        'error_message': message,
      };

  /// The real POST /inventory-imports body: `excel_import_service.create_import`
  /// returns the row array under **"preview"**, plus `idempotent_replay`.
  Map<String, dynamic> previewJson({
    required List<Map<String, dynamic>> rows,
    bool replay = false,
    int total = 4,
    int valid = 2,
    int errors = 2,
  }) =>
      {
        'id': 7,
        'filename': 'stock.xlsx',
        'status': 'VALIDATED',
        'total_rows': total,
        'valid_rows': valid,
        'error_rows': errors,
        'preview': rows,
        'idempotent_replay': replay,
      };

  /// The GET …/inventory-imports/{job} body: same job, rows under **"rows"**.
  Map<String, dynamic> getPreviewJson({
    required List<Map<String, dynamic>> rows,
  }) =>
      {
        'id': 7,
        'filename': 'stock.xlsx',
        'status': 'VALIDATED',
        'total_rows': rows.length,
        'valid_rows': rows.where((r) => r['status'] == 'VALID').length,
        'error_rows':
            rows.where((r) => r['status'] == 'ERROR').length,
        'rows': rows,
      };

  ProviderContainer makeContainer(
    FakeImportRepo repo, {
    WorkbookPickerService? picker,
  }) {
    final container = ProviderContainer(overrides: [
      inventoryImportRepositoryProvider.overrideWithValue(repo),
      workbookPickerProvider
          .overrideWithValue(picker ?? FakePicker()),
      tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(accessToken: 'test-access-token')),
      selectedShopProvider
          .overrideWith(() => SelectedShopOverride(ownerShop(id: 10))),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  // ── §133: valid file ──────────────────────────────────────────────────────
  group('valid file', () {
    test('a good upload lands on the preview, never straight into inventory',
        () async {
      // §40 "Never immediately push an unreviewed file": the upload only ever
      // stages rows; nothing is applied until confirm().
      final repo = FakeImportRepo(
        onUpload: ImportPreview(
          meta: job(),
          rows: [
            ImportRow(rowNumber: 1, status: 'VALID', productName: 'Rice'),
            ImportRow(rowNumber: 2, status: 'VALID', productName: 'Tea'),
          ],
        ),
      );
      final container = makeContainer(repo);

      await container.read(importControllerProvider.notifier).pickAndUpload();

      final state = container.read(importControllerProvider);
      expect(state.status, ImportStatus.preview);
      expect(state.preview!.validCount, 2);
      expect(repo.confirmCalls, 0, reason: 'uploading must not apply rows');
    });
  });

  // ── §133: invalid / empty / large file ────────────────────────────────────
  group('invalid file, empty file, large file', () {
    Future<ImportState> uploadExpectingError(Object error) async {
      final container = makeContainer(FakeImportRepo(error: error));
      await container.read(importControllerProvider.notifier).pickAndUpload();
      return container.read(importControllerProvider);
    }

    test('a wrong file type keeps the backend\'s reason', () async {
      // `validate_upload` → "Unsupported file type. Allowed: .xlsx"
      final state = await uploadExpectingError(
        const ApiException(
          statusCode: 400,
          message: 'Unsupported file type. Allowed: .xlsx',
        ),
      );

      expect(state.status, ImportStatus.error);
      // The shopkeeper must learn WHICH file problem it was, not just that
      // "something went wrong".
      expect(state.message, 'Unsupported file type. Allowed: .xlsx');
    });

    test('a non-workbook disguised with an .xlsx name is refused readably',
        () async {
      // The backend checks the ZIP magic header, so a renamed .txt cannot pass.
      final state = await uploadExpectingError(
        const ApiException(
          statusCode: 400,
          message: 'File content does not match its extension',
        ),
      );

      expect(state.message, 'File content does not match its extension');
    });

    test('an empty file says so, instead of reporting a generic failure',
        () async {
      // `EMPTY_FILE` from upload_security — a real, common mistake (the shop
      // saved the workbook before typing anything into it).
      final state = await uploadExpectingError(
        const ApiException(statusCode: 400, message: 'Uploaded file is empty'),
      );

      expect(state.status, ImportStatus.error);
      expect(state.message, 'Uploaded file is empty');
    });

    test('an oversized file explains the limit rather than failing silently',
        () async {
      final state = await uploadExpectingError(
        const ApiException(
          statusCode: 413,
          message: 'File is too large. Maximum size is 10MB.',
        ),
      );

      expect(state.message, 'File is too large. Maximum size is 10MB.');
    });

    test('an empty file never reaches the confirmation step', () async {
      final repo = FakeImportRepo(
        error: const ApiException(message: 'Uploaded file is empty'),
      );
      final container = makeContainer(repo);
      final notifier = container.read(importControllerProvider.notifier);

      await notifier.pickAndUpload();
      await notifier.confirm();

      expect(repo.confirmCalls, 0);
      expect(container.read(importControllerProvider).status,
          ImportStatus.error);
    });
  });

  // ── §133: cancelled picker ────────────────────────────────────────────────
  group('cancelled picker', () {
    test('cancelling stays idle and never touches the repository', () async {
      final repo = FakeImportRepo();
      final picker = FakePicker(shouldCancel: true);
      final container = makeContainer(repo, picker: picker);

      await container.read(importControllerProvider.notifier).pickAndUpload();

      final state = container.read(importControllerProvider);
      expect(picker.calls, 1);
      // Silence, not an error: the shopkeeper changed their mind.
      expect(state.status, ImportStatus.idle);
      expect(state.message, isNull);
      expect(repo.uploadCalls, 0);
    });

    test('cancelling after a successful upload keeps the existing preview',
        () async {
      // Cancelling a second pick must not wipe the preview already on screen.
      final repo = FakeImportRepo(
        onUpload: ImportPreview(
          meta: job(),
          rows: [ImportRow(rowNumber: 1, status: 'VALID')],
        ),
      );
      final picker = FakePicker();
      final container = makeContainer(repo, picker: picker);

      await container.read(importControllerProvider.notifier).pickAndUpload();
      picker.shouldCancel = true;
      await container.read(importControllerProvider.notifier).pickAndUpload();

      final state = container.read(importControllerProvider);
      expect(state.status, ImportStatus.preview);
      expect(state.preview!.validCount, 1);
    });
  });

  // ── §133: duplicate barcode / invalid price / row errors ─────────────────
  group('duplicate barcode and invalid price', () {
    test('rows are read from BOTH endpoint shapes', () {
      // The bug this pins: `create_import` returns the array under "preview"
      // and `get_import_preview` returns it under "rows". Only the GET shape
      // was parsed, so after an UPLOAD — the path the shopkeeper actually lands
      // on — the preview had no rows at all and the screen showed "No rows
      // found in this file" while the job counters said otherwise.
      final rows = [
        rowJson(1, name: 'Rice'),
        rowJson(
          2,
          status: 'ERROR',
          code: 'INVALID_BARCODE',
          field: 'barcode',
          message: 'Barcode format invalid (bad check digit)',
        ),
      ];

      final fromUpload = ImportPreview.fromJson(previewJson(rows: rows));
      final fromFetch = ImportPreview.fromJson(getPreviewJson(rows: rows));

      for (final preview in [fromUpload, fromFetch]) {
        expect(preview.rows, hasLength(2));
        expect(preview.validCount, 1);
        expect(preview.errorCount, 1);
        expect(preview.rows.last.errorField, 'barcode');
        expect(preview.rows.last.errorCode, 'INVALID_BARCODE');
      }
    });

    test('a duplicate row is counted separately from other errors', () {
      // §41 lists Total / Valid / Invalid / **Duplicate** as four numbers. A
      // repeated line is a different mistake from a bad price, and the backend
      // already tags it DUPLICATE_ROW, so the count is computable.
      final preview = ImportPreview.fromJson(previewJson(rows: [
        rowJson(1, name: 'Rice'),
        rowJson(2, name: 'Tea'),
        rowJson(
          3,
          status: 'ERROR',
          code: 'DUPLICATE_ROW',
          field: 'row',
          message: 'Duplicate of an earlier row in this file',
          name: 'Rice',
        ),
        rowJson(
          4,
          status: 'ERROR',
          code: 'DUPLICATE_ROW',
          field: 'row',
          message: 'Duplicate of an earlier row in this file',
          name: 'Tea',
        ),
      ]));

      expect(preview.rows, hasLength(4));
      expect(preview.validCount, 2);
      expect(preview.errorCount, 2);
      // 2 duplicates, and they are ALSO 2 of the errors — the chip is a
      // breakdown of the errors, not an extra bucket.
      expect(preview.duplicateCount, 2);
      expect(preview.rows[2].isDuplicate, isTrue);
      expect(preview.rows[1].isDuplicate, isFalse);
    });

    test('an invalid price names the field that has to be fixed', () {
      // §42 requires Row number / Field / Error / Suggested action. The
      // backend sends `error_field`; it used to be dropped entirely.
      final preview = ImportPreview.fromJson(previewJson(rows: [
        rowJson(1, name: 'Rice'),
        rowJson(
          5,
          status: 'ERROR',
          code: 'NEGATIVE_PRICE',
          field: 'price',
          message: 'Price cannot be negative',
          name: 'Salt',
        ),
      ]));

      final bad = preview.rows.singleWhere((r) => r.isError);
      expect(bad.rowNumber, 5);
      expect(bad.errorField, 'price');
      expect(bad.errorCode, 'NEGATIVE_PRICE');
      expect(bad.errorMessage, 'Price cannot be negative');
    });

    test('every row error the backend can raise survives parsing', () {
      // The vocabulary `excel_import_service` actually emits, so a new code in
      // one of these slots cannot silently vanish.
      const codes = <String, String>{
        'MISSING_REQUIRED_FIELD': 'price',
        'INVALID_NUMBER': 'price',
        'NEGATIVE_PRICE': 'mrp',
        'PRICE_EXCEEDS_MRP': 'mrp',
        'INVALID_BARCODE': 'barcode',
        'DUPLICATE_ROW': 'row',
        'UNKNOWN_PRODUCT': 'barcode',
      };
      for (final entry in codes.entries) {
        final preview = ImportPreview.fromJson(previewJson(rows: [
          rowJson(
            9,
            status: 'ERROR',
            code: entry.key,
            field: entry.value,
            message: 'msg for ${entry.key}',
          ),
        ]));
        expect(preview.rows.single.errorCode, entry.key);
        expect(preview.rows.single.errorField, entry.value);
        expect(preview.errorCount, 1);
      }
    });

    test('a summarised large import invents no duplicate count', () {
      // A large import ships counters only, no row array. Reporting "0
      // duplicates" there would be a claim the app cannot support.
      final preview = ImportPreview.fromJson({
        'id': 7,
        'filename': 'big.xlsx',
        'status': 'VALIDATED',
        'total_rows': 5000,
        'valid_rows': 4982,
        'error_rows': 18,
      });

      expect(preview.rows, isEmpty);
      expect(preview.duplicateCount, 0);
      // The counters still work, so Confirm is never wrongly disabled.
      expect(preview.validCount, 4982);
      expect(preview.errorCount, 18);
    });
  });

  // ── §133: duplicate UPLOAD (idempotent replay) ────────────────────────────
  group('duplicate upload', () {
    test('a replayed file is flagged, never passed off as a fresh upload',
        () async {
      // The backend deduplicates on file content and returns the EARLIER job
      // with `idempotent_replay: true`. The app ignored the flag, so a
      // shopkeeper who re-uploaded the same file was shown the previous
      // job's rows as if they were the file just picked — and "Apply valid
      // rows" applied the OLD staged rows.
      final preview = ImportPreview.fromJson(previewJson(
        rows: [rowJson(1, name: 'Rice')],
        replay: true,
      ));
      expect(preview.isIdempotentReplay, isTrue);

      // A normal first upload is not flagged.
      expect(
        ImportPreview.fromJson(previewJson(rows: [rowJson(1)]))
            .isIdempotentReplay,
        isFalse,
      );
      // A backend that omits the key entirely is treated as "not a replay"
      // rather than crashing the whole preview.
      final legacy = ImportPreview.fromJson({
        'id': 7,
        'filename': 'stock.xlsx',
        'status': 'VALIDATED',
        'total_rows': 1,
        'valid_rows': 1,
        'error_rows': 0,
      });
      expect(legacy.isIdempotentReplay, isFalse);
    });
  });

  // ── §133: partial success / server failure / retry ────────────────────────
  group('partial success, server failure and retry', () {
    test('a partial result is reported as partial, never as full success',
        () async {
      // §43: 500 processed / 482 ok / 18 failed. "Do not hide partial
      // failures" — the counts have to survive into the done state.
      final repo = FakeImportRepo(
        onUpload: ImportPreview(
          meta: job(total: 500, valid: 500, errors: 0),
          rows: [ImportRow(rowNumber: 1, status: 'VALID')],
        ),
        onConfirm: ImportConfirmResult(
          jobId: 7,
          processed: 500,
          failed: 18,
        ),
      );
      final container = makeContainer(repo);
      final notifier = container.read(importControllerProvider.notifier);

      await notifier.pickAndUpload();
      await notifier.confirm();

      final result = container.read(importControllerProvider).result!;
      expect(result.processed, 500);
      // 18 of 500 failed — the model carries processed/failed and the success
      // count is the remainder, so 18 can never be quietly rounded away.
      expect(result.failed, 18);
      expect(result.processed - result.failed, 482);
      expect(result.queued, isFalse);
      expect(container.read(importControllerProvider).status, ImportStatus.done);
    });

    test('a failed confirm keeps the staged preview so a retry can work',
        () async {
      // §42 lists Retry. The rows are already staged server-side, so the
      // shopkeeper must be able to try again WITHOUT re-picking the file.
      final repo = FakeImportRepo(
        onUpload: ImportPreview(
          meta: job(),
          rows: [ImportRow(rowNumber: 1, status: 'VALID', productName: 'Rice')],
        ),
      )..confirmError = const ApiException(
          statusCode: 503,
          message: 'Import service is busy. Please retry.',
        );
      final container = makeContainer(repo);
      final notifier = container.read(importControllerProvider.notifier);

      await notifier.pickAndUpload();
      await notifier.confirm();

      final state = container.read(importControllerProvider);
      expect(state.status, ImportStatus.error);
      expect(state.message, 'Import service is busy. Please retry.');
      // The staged job id survives, so confirm() can be retried directly.
      expect(state.preview!.meta.id, 7);
    });

    test('an offline upload explains itself instead of saying "Upload failed"',
        () async {
      final container = makeContainer(
        FakeImportRepo(
          error: const ApiException(statusCode: null, message: 'Network error'),
        ),
      );

      await container.read(importControllerProvider.notifier).pickAndUpload();

      final state = container.read(importControllerProvider);
      expect(state.status, ImportStatus.error);
      expect(state.message, contains('internet'));
    });

    test('a retry after a failure succeeds once the backend recovers', () async {
      final repo = FakeImportRepo(
        onUpload: ImportPreview(
          meta: job(),
          rows: [ImportRow(rowNumber: 1, status: 'VALID', productName: 'Rice')],
        ),
      )..uploadError = const ApiException(
          statusCode: 503,
          message: 'Import service is busy. Please retry.',
        );
      final container = makeContainer(repo);
      final notifier = container.read(importControllerProvider.notifier);

      await notifier.pickAndUpload();
      expect(container.read(importControllerProvider).status,
          ImportStatus.error);

      // The shopkeeper taps Retry and the backend is healthy again.
      repo.uploadError = null;
      await notifier.pickAndUpload();

      final state = container.read(importControllerProvider);
      expect(state.status, ImportStatus.preview);
      expect(state.preview!.validCount, 1);
      expect(repo.uploadCalls, 2);
      // The error from the failed attempt must not linger over the new preview.
      expect(state.message, isNull);
    });
  });

  // ── What the preview actually shows (§41 + §42) ──────────────────────────
  group('ImportPreviewScreen — the summary and the rows', () {
    Future<void> pumpPreview(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ImportPreviewScreen()),
      ));
      await tester.pumpAndSettle();
    }

    /// Drives the REAL flow (picker → upload → controller → screen), so these
    /// assertions cover the parsed payload, not a hand-built widget.
    Future<ProviderContainer> pumped(
      WidgetTester tester, {
      required List<Map<String, dynamic>> rows,
      bool replay = false,
      int total = 4,
      int valid = 2,
      int errors = 2,
    }) async {
      final repo = FakeImportRepo(
        onUpload: ImportPreview.fromJson(previewJson(
          rows: rows,
          replay: replay,
          total: total,
          valid: valid,
          errors: errors,
        )),
      );
      final container = makeContainer(repo);
      await container.read(importControllerProvider.notifier).pickAndUpload();
      await pumpPreview(tester, container);
      return container;
    }

    testWidgets('a duplicate upload says so, and the preview still renders',
        (tester) async {
      await pumped(
        tester,
        rows: [rowJson(1, name: 'Rice'), rowJson(2, name: 'Tea')],
        replay: true,
      );

      expect(find.byKey(const Key('import-replay-notice')), findsOneWidget);
      expect(find.textContaining('already uploaded'), findsOneWidget);
      // The shopkeeper can still review and apply — the notice informs, it does
      // not block a legitimate re-confirm of the same staged job. The row title
      // is composed as "Row N · Name", so match on the product.
      expect(find.textContaining('Rice'), findsOneWidget);
      expect(find.textContaining('Tea'), findsOneWidget);
    });

    testWidgets('a fresh upload carries no replay notice', (tester) async {
      await pumped(tester, rows: [rowJson(1, name: 'Rice')]);

      expect(find.byKey(const Key('import-replay-notice')), findsNothing);
    });

    testWidgets('duplicates get their own chip when the file has any',
        (tester) async {
      await pumped(
        tester,
        rows: [
          rowJson(1, name: 'Rice'),
          rowJson(2, name: 'Tea'),
          rowJson(
            3,
            status: 'ERROR',
            code: 'DUPLICATE_ROW',
            field: 'row',
            message: 'Duplicate of an earlier row in this file',
            name: 'Rice',
          ),
        ],
        total: 3,
        valid: 2,
        errors: 1,
      );

      expect(find.byKey(const Key('import-chip-duplicates')), findsOneWidget);
      // Total / Valid / Errors stay — the duplicate chip is a fourth number.
      expect(find.byKey(const Key('import-chip-total')), findsOneWidget);
      expect(find.byKey(const Key('import-chip-valid')), findsOneWidget);
      expect(find.byKey(const Key('import-chip-errors')), findsOneWidget);
    });

    testWidgets('no duplicate chip when the file has none', (tester) async {
      await pumped(
        tester,
        rows: [rowJson(1, name: 'Rice'), rowJson(2, name: 'Tea')],
      );

      // Absent rather than "0" — a summarised import must not claim it knows.
      expect(find.byKey(const Key('import-chip-duplicates')), findsNothing);
    });

    testWidgets('an error row names the field to fix', (tester) async {
      await pumped(
        tester,
        rows: [
          rowJson(1, name: 'Rice'),
          rowJson(
            5,
            status: 'ERROR',
            code: 'NEGATIVE_PRICE',
            field: 'price',
            message: 'Price cannot be negative',
            name: 'Salt',
          ),
        ],
      );

      // §42: Row number, Field, Error. The field leads so the shopkeeper knows
      // which cell to open before reading why it was rejected.
      expect(find.textContaining('price · NEGATIVE_PRICE'), findsOneWidget);
      expect(find.textContaining('Price cannot be negative'), findsOneWidget);
    });

    testWidgets('an error row with no field still renders the code', (tester) async {
      // Older payloads carry no `error_field`; the row must not render a
      // dangling separator or an empty label.
      await pumped(
        tester,
        rows: [
          rowJson(
            5,
            status: 'ERROR',
            code: 'UNKNOWN_PRODUCT',
            message: 'No catalog product registered for this barcode',
          ),
        ],
        total: 1,
        valid: 0,
        errors: 1,
      );

      expect(find.textContaining('UNKNOWN_PRODUCT'), findsOneWidget);
      expect(find.textContaining('· ·'), findsNothing);
    });
  });
}