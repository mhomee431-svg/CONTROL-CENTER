import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/data/import_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/domain/import_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/presentation/controllers/import_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/presentation/screens/inventory_import_screen.dart';

import 'fakes.dart';

/// Fake workbook picker that returns a canned workbook (no platform channels).
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

/// Fake save dialog for Download Sample: records what was offered and can
/// gate completion so the in-flight guard is testable.
class FakeWorkbookSaver implements WorkbookSaveService {
  FakeWorkbookSaver({this.shouldSave = true, this.gate});

  bool shouldSave;

  /// When set, [saveWorkbook] blocks until it is completed.
  Completer<bool>? gate;

  int calls = 0;
  final List<String> savedNames = [];
  final List<Uint8List> savedBytes = [];

  @override
  Future<bool> saveWorkbook(String fileName, Uint8List bytes) async {
    calls++;
    savedNames.add(fileName);
    savedBytes.add(bytes);
    if (gate != null) return gate!.future;
    return shouldSave;
  }
}

void main() {
  group('InventoryImportController', () {
    test('upload success moves to preview with row outcomes', () async {
      final fake = FakeImportRepo(
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
            ImportRow(
              rowNumber: 3,
              status: 'ERROR',
              errorCode: 'MISSING_PRICE',
              errorMessage: 'Price is required',
            ),
          ],
        ),
      );
      final picker = FakeWorkbookPicker();
      final container = ProviderContainer(
        overrides: [
          inventoryImportRepositoryProvider.overrideWithValue(fake),
          workbookPickerProvider.overrideWithValue(picker),
          tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'tok'),
          ),
          selectedShopProvider.overrideWith(
            () => SelectedShopOverride(ownerShop()),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(importControllerProvider.notifier).pickAndUpload();

      final state = container.read(importControllerProvider);
      expect(state.status, ImportStatus.preview);
      expect(state.preview, isNotNull);
      expect(state.preview!.meta.id, 42);
      expect(state.preview!.meta.validRows, 8);
      expect(state.preview!.meta.errorRows, 2);
      expect(state.preview!.rows, hasLength(1));
      expect(state.preview!.rows.first.rowNumber, 3);
      expect(fake.uploadCalls, 1);
      expect(fake.lastShopId, 10);
      expect(picker.calls, 1);
    });

    test('upload failure surfaces a friendly error message', () async {
      final fake = FakeImportRepo(
        error: const ApiException(
          statusCode: 413,
          message: 'File is too large',
        ),
      );
      final picker = FakeWorkbookPicker();
      final container = ProviderContainer(
        overrides: [
          inventoryImportRepositoryProvider.overrideWithValue(fake),
          workbookPickerProvider.overrideWithValue(picker),
          tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'tok'),
          ),
          selectedShopProvider.overrideWith(
            () => SelectedShopOverride(ownerShop()),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(importControllerProvider.notifier).pickAndUpload();

      final state = container.read(importControllerProvider);
      expect(state.status, ImportStatus.error);
      expect(state.message, isNotNull);
      expect(state.message, contains('too large'));
    });

    test(
      'network failure during upload surfaces a connectivity message',
      () async {
        final fake = FakeImportRepo(
          error: const ApiException(message: 'Network error'),
        );
        final picker = FakeWorkbookPicker();
        final container = ProviderContainer(
          overrides: [
            inventoryImportRepositoryProvider.overrideWithValue(fake),
            workbookPickerProvider.overrideWithValue(picker),
            tokenStoreProvider.overrideWithValue(
              InMemoryTokenStore(accessToken: 'tok'),
            ),
            selectedShopProvider.overrideWith(
              () => SelectedShopOverride(ownerShop()),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(importControllerProvider.notifier).pickAndUpload();

        final state = container.read(importControllerProvider);
        expect(state.status, ImportStatus.error);
        expect(state.message, contains('internet'));
      },
    );

    test('user cancelling the picker stays idle', () async {
      final fake = FakeImportRepo();
      final picker = FakeWorkbookPicker(shouldCancel: true);
      final container = ProviderContainer(
        overrides: [
          inventoryImportRepositoryProvider.overrideWithValue(fake),
          workbookPickerProvider.overrideWithValue(picker),
          tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'tok'),
          ),
          selectedShopProvider.overrideWith(
            () => SelectedShopOverride(ownerShop()),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(importControllerProvider.notifier).pickAndUpload();

      final state = container.read(importControllerProvider);
      expect(state.status, ImportStatus.idle);
      expect(fake.uploadCalls, 0);
    });

    test('no selected shop → error without touching the repo', () async {
      final fake = FakeImportRepo();
      final picker = FakeWorkbookPicker();
      final container = ProviderContainer(
        overrides: [
          inventoryImportRepositoryProvider.overrideWithValue(fake),
          workbookPickerProvider.overrideWithValue(picker),
          tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'tok'),
          ),
          selectedShopProvider.overrideWith(() => SelectedShopOverride(null)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(importControllerProvider.notifier).pickAndUpload();

      final state = container.read(importControllerProvider);
      expect(state.status, ImportStatus.error);
      expect(state.message, 'No shop selected');
      expect(fake.uploadCalls, 0);
      expect(picker.calls, 0);
    });

    test('confirm moves to done with processed counts', () async {
      final fake = FakeImportRepo(
        onUpload: ImportPreview(
          meta: const ImportJob(
            id: 7,
            filename: 's.xlsx',
            status: 'VALIDATED',
            totalRows: 5,
            validRows: 5,
            errorRows: 0,
          ),
        ),
        onConfirm: const ImportConfirmResult(processed: 5, failed: 0),
      );
      final picker = FakeWorkbookPicker();
      final container = ProviderContainer(
        overrides: [
          inventoryImportRepositoryProvider.overrideWithValue(fake),
          workbookPickerProvider.overrideWithValue(picker),
          tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'tok'),
          ),
          selectedShopProvider.overrideWith(
            () => SelectedShopOverride(ownerShop()),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(importControllerProvider.notifier).pickAndUpload();
      expect(
        container.read(importControllerProvider).status,
        ImportStatus.preview,
      );

      await container.read(importControllerProvider.notifier).confirm();

      final state = container.read(importControllerProvider);
      expect(state.status, ImportStatus.done);
      expect(state.result, isNotNull);
      expect(state.result!.processed, 5);
      expect(state.result!.failed, 0);
      expect(fake.confirmCalls, 1);
    });

    test('confirm failure surfaces a friendly error', () async {
      final fake = FakeImportRepo(
        onUpload: ImportPreview(
          meta: const ImportJob(
            id: 7,
            filename: 's.xlsx',
            status: 'VALIDATED',
            totalRows: 5,
            validRows: 5,
            errorRows: 0,
          ),
        ),
        error: const ApiException(
          statusCode: 403,
          message: 'You do not have permission',
        ),
      );
      final picker = FakeWorkbookPicker();
      final container = ProviderContainer(
        overrides: [
          inventoryImportRepositoryProvider.overrideWithValue(fake),
          workbookPickerProvider.overrideWithValue(picker),
          tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'tok'),
          ),
          selectedShopProvider.overrideWith(
            () => SelectedShopOverride(ownerShop()),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(importControllerProvider.notifier).pickAndUpload();
      await container.read(importControllerProvider.notifier).confirm();

      final state = container.read(importControllerProvider);
      expect(state.status, ImportStatus.error);
      expect(state.message, contains('permission'));
    });

    test('loadJobs populates the recent-jobs list', () async {
      final fake = FakeImportRepo(
        onList: const [
          ImportJob(
            id: 1,
            filename: 'a.xlsx',
            status: 'COMPLETED',
            totalRows: 10,
            validRows: 10,
            errorRows: 0,
          ),
          ImportJob(
            id: 2,
            filename: 'b.xlsx',
            status: 'FAILED',
            totalRows: 3,
            validRows: 0,
            errorRows: 3,
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          inventoryImportRepositoryProvider.overrideWithValue(fake),
          tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'tok'),
          ),
          selectedShopProvider.overrideWith(
            () => SelectedShopOverride(ownerShop()),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(importControllerProvider.notifier).loadJobs();

      final state = container.read(importControllerProvider);
      expect(state.jobs, hasLength(2));
      expect(state.jobs.first.filename, 'a.xlsx');
      expect(state.jobs.first.status, 'COMPLETED');
      expect(state.jobs.last.status, 'FAILED');
    });

    test('reset clears all cached import state', () async {
      final fake = FakeImportRepo(
        onUpload: ImportPreview(
          meta: const ImportJob(
            id: 1,
            filename: 's.xlsx',
            status: 'VALIDATED',
            totalRows: 5,
            validRows: 5,
            errorRows: 0,
          ),
        ),
      );
      final picker = FakeWorkbookPicker();
      final container = ProviderContainer(
        overrides: [
          inventoryImportRepositoryProvider.overrideWithValue(fake),
          workbookPickerProvider.overrideWithValue(picker),
          tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'tok'),
          ),
          selectedShopProvider.overrideWith(
            () => SelectedShopOverride(ownerShop()),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(importControllerProvider.notifier).pickAndUpload();
      expect(
        container.read(importControllerProvider).status,
        ImportStatus.preview,
      );

      container.read(importControllerProvider.notifier).reset();

      final state = container.read(importControllerProvider);
      expect(state.status, ImportStatus.idle);
      expect(state.preview, isNull);
      expect(state.jobs, isEmpty);
    });

    test('resetFlow keeps recent jobs but clears the active flow', () async {
      final fake = FakeImportRepo(
        onUpload: ImportPreview(
          meta: const ImportJob(
            id: 1,
            filename: 's.xlsx',
            status: 'VALIDATED',
            totalRows: 5,
            validRows: 5,
            errorRows: 0,
          ),
        ),
        onList: const [
          ImportJob(
            id: 99,
            filename: 'old.xlsx',
            status: 'COMPLETED',
            totalRows: 2,
            validRows: 2,
            errorRows: 0,
          ),
        ],
      );
      final picker = FakeWorkbookPicker();
      final container = ProviderContainer(
        overrides: [
          inventoryImportRepositoryProvider.overrideWithValue(fake),
          workbookPickerProvider.overrideWithValue(picker),
          tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'tok'),
          ),
          selectedShopProvider.overrideWith(
            () => SelectedShopOverride(ownerShop()),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(importControllerProvider.notifier).pickAndUpload();
      await container.read(importControllerProvider.notifier).loadJobs();
      container.read(importControllerProvider.notifier).resetFlow();

      final state = container.read(importControllerProvider);
      expect(state.status, ImportStatus.idle);
      expect(state.preview, isNull);
      expect(state.jobs, hasLength(1));
      expect(state.jobs.first.filename, 'old.xlsx');
    });
  });

  group('SampleDownloadController — Download Sample', () {
    ProviderContainer makeContainer({
      required FakeImportRepo repo,
      required FakeWorkbookSaver saver,
      int? shopId = 10,
    }) {
      final container = ProviderContainer(overrides: [
        inventoryImportRepositoryProvider.overrideWithValue(repo),
        workbookPickerProvider.overrideWithValue(FakeWorkbookPicker()),
        workbookSaveProvider.overrideWithValue(saver),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider.overrideWith(
            () => SelectedShopOverride(shopId == null ? null : ownerShop(id: shopId))),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('downloads the template and hands it to the save dialog',
        () async {
      final repo = FakeImportRepo();
      final saver = FakeWorkbookSaver();
      final container = makeContainer(repo: repo, saver: saver);

      await container.read(sampleDownloadProvider.notifier).download();

      expect(repo.sampleCalls, 1);
      expect(repo.lastSampleShopId, 10);
      expect(saver.savedNames.single, sampleWorkbookFileName);
      expect(saver.savedBytes.single, isNotEmpty);
      expect(container.read(sampleDownloadProvider).message,
          'Sample workbook saved');
    });

    test('a dismissed save dialog is silent, not an error', () async {
      final repo = FakeImportRepo();
      final saver = FakeWorkbookSaver(shouldSave: false);
      final container = makeContainer(repo: repo, saver: saver);

      await container.read(sampleDownloadProvider.notifier).download();

      expect(repo.sampleCalls, 1);
      expect(saver.calls, 1);
      expect(container.read(sampleDownloadProvider).message, isNull);
    });

    test('a download failure reports copy and never reaches the saver',
        () async {
      final repo = FakeImportRepo(
        error: const ApiException(statusCode: null, message: 'Network error'),
      );
      final saver = FakeWorkbookSaver();
      final container = makeContainer(repo: repo, saver: saver);

      await container.read(sampleDownloadProvider.notifier).download();

      expect(repo.sampleCalls, 1);
      expect(saver.calls, 0);
      expect(container.read(sampleDownloadProvider).message,
          contains('internet'));
    });

    test('without a shop the sample is never requested', () async {
      final repo = FakeImportRepo();
      final saver = FakeWorkbookSaver();
      final container = makeContainer(repo: repo, saver: saver, shopId: null);

      await container.read(sampleDownloadProvider.notifier).download();

      expect(repo.sampleCalls, 0);
      expect(container.read(sampleDownloadProvider).message,
          'Select a shop first.');
    });

    test('a second download while one is in flight is ignored', () async {
      final saver = FakeWorkbookSaver(gate: Completer<bool>());
      final container = makeContainer(repo: FakeImportRepo(), saver: saver);

      final first = container.read(sampleDownloadProvider.notifier).download();
      // Let the first attempt reach the (gated) save dialog.
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      await container.read(sampleDownloadProvider.notifier).download();

      expect(saver.calls, 1);
      saver.gate!.complete(true);
      await first;
      expect(container.read(sampleDownloadProvider).message,
          'Sample workbook saved');
    });
  });

  group('InventoryImportScreen — Download Sample (widget)', () {
    testWidgets('offers the sample download and reports the save',
        (tester) async {
      final repo = FakeImportRepo();
      final saver = FakeWorkbookSaver();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          inventoryImportRepositoryProvider.overrideWithValue(repo),
          workbookSaveProvider.overrideWithValue(saver),
          tokenStoreProvider.overrideWithValue(
              InMemoryTokenStore(accessToken: 'test-access-token')),
          selectedShopProvider
              .overrideWith(() => SelectedShopOverride(ownerShop())),
        ],
        child: const MaterialApp(home: InventoryImportScreen()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Choose Excel file'), findsOneWidget);
      expect(find.text('Download sample'), findsOneWidget);

      await tester.tap(find.text('Download sample'));
      await tester.pumpAndSettle();

      expect(repo.sampleCalls, 1);
      expect(repo.lastSampleShopId, 10);
      expect(saver.calls, 1);
      expect(saver.savedNames.single, sampleWorkbookFileName);
      expect(saver.savedBytes.single, isNotEmpty);
      expect(find.text('Sample workbook saved'), findsOneWidget);

      // Let the snackbar time out so no timer outlives the test.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });
}
