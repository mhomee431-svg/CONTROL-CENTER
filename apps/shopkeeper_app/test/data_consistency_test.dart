import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/data/import_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/domain/import_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/presentation/controllers/import_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/controllers/products_controller.dart';

import 'fakes.dart';

/// Canned workbook - the real file picker needs a platform channel.
class _StubPicker implements WorkbookPickerService {
  @override
  Future<PickedWorkbook?> pick() async =>
      const PickedWorkbook(path: '/tmp/test.xlsx', name: 'test.xlsx');
}

/// DATA CONSISTENCY: after a successful mutation the repository must agree
/// with the backend.
///
/// The app's rule everywhere else is to reconcile from the SERVER's response
/// rather than re-deriving locally - stock takes the server's `newQuantity`,
/// a product add uses the created row, notifications roll back on failure.
///
/// The import case is the one that genuinely regressed. The app is a
/// StatefulShellBranch, so the Products tab stays MOUNTED behind the pushed
/// import route and its `initState` never re-runs on the way back. With no
/// explicit refresh, the shopkeeper kept reading pre-import rows.
///
/// These assert on DATA, not call counts: the fake's `items` is swapped to
/// represent "the server's catalog changed", so a pass means the controller
/// really adopted the new rows.
void main() {
  /// Canned workbook: the real picker needs a platform channel.
  final picker = _StubPicker();

  const stagedJob = ImportJob(
    id: 42,
    filename: 'stock.xlsx',
    status: 'VALIDATED',
    totalRows: 10,
    validRows: 10,
    errorRows: 0,
  );

  ImportPreview staged() => const ImportPreview(meta: stagedJob);

  ShopProductItem row(int id, {int quantity = 5, String name = 'Parle-G'}) =>
      ShopProductItem(
        id: id,
        name: name,
        status: 'ACTIVE',
        price: 10,
        sku: 'SKU$id',
        brand: 'Parle',
        isActive: true,
        isAvailable: true,
        quantity: quantity,
        stockStatus: 'IN_STOCK',
      );

  ProviderContainer makeContainer({
    required FakeImportRepo importRepo,
    required FakeProductRepo productRepo,
  }) {
    final container = ProviderContainer(overrides: [
      inventoryImportRepositoryProvider.overrideWithValue(importRepo),
      productRepositoryProvider.overrideWithValue(productRepo),
      inventoryRepositoryProvider.overrideWithValue(productRepo),
      workbookPickerProvider.overrideWithValue(picker),
      tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(accessToken: 'test-access-token')),
      selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  group('import completion reconciles the catalog', () {
    test('a completed import adopts the post-import catalog', () async {
      final importRepo = FakeImportRepo(
        onUpload: staged(),
        onConfirm: const ImportConfirmResult(processed: 12, failed: 0),
      );
      // The catalog as it stands BEFORE the import is applied.
      final productRepo = FakeProductRepo(items: [row(1)]);
      final container =
          makeContainer(importRepo: importRepo, productRepo: productRepo);

      // Load the pre-import catalog, exactly as the mounted Products tab would.
      await container.read(productsControllerProvider.notifier).load();
      expect(container.read(productsControllerProvider).items, hasLength(1));

      // The server's catalog changes underneath us (the import writes rows).
      productRepo.items = [row(1, quantity: 40), row(2, name: 'Lays')];

      final controller = container.read(importControllerProvider.notifier);
      await controller.pickAndUpload();
      expect(container.read(importControllerProvider).status,
          ImportStatus.preview);

      await controller.confirm();
      expect(container.read(importControllerProvider).status, ImportStatus.done);
      await Future<void>.delayed(Duration.zero);

      // The repository now agrees with the backend.
      final items = container.read(productsControllerProvider).items;
      expect(items.map((i) => i.id), containsAll(<int>[1, 2]));
      expect(items.firstWhere((i) => i.id == 1).quantity, 40);
    });

    test('a QUEUED import does not race the background job', () async {
      final importRepo = FakeImportRepo(
        onUpload: staged(),
        // Large imports run in the background: the rows are not written yet.
        onConfirm:
            const ImportConfirmResult(processed: 0, failed: 0, queued: true),
      );
      final productRepo = FakeProductRepo(items: [row(1)]);
      final container =
          makeContainer(importRepo: importRepo, productRepo: productRepo);

      await container.read(productsControllerProvider.notifier).load();
      productRepo.items = [row(1), row(2, name: 'Lays')];

      final controller = container.read(importControllerProvider.notifier);
      await controller.pickAndUpload();
      await controller.confirm();
      await Future<void>.delayed(Duration.zero);

      // Refetching now would fetch PRE-import rows and cache them as current,
      // so the queued case deliberately waits for the next natural read.
      expect(container.read(productsControllerProvider).items, hasLength(1),
          reason: 'a queued job is still running; do not race it');
    });

    test('a FAILED import leaves the catalog untouched', () async {
      final importRepo = FakeImportRepo(
        onUpload: staged(),
        error: const ApiException(message: 'server said no'),
      );
      final productRepo = FakeProductRepo(items: [row(1)]);
      final container =
          makeContainer(importRepo: importRepo, productRepo: productRepo);

      await container.read(productsControllerProvider.notifier).load();
      productRepo.items = [row(1), row(2, name: 'Lays')];

      final controller = container.read(importControllerProvider.notifier);
      await controller.pickAndUpload();
      await controller.confirm();

      expect(container.read(importControllerProvider).status, ImportStatus.error);
      await Future<void>.delayed(Duration.zero);

      // A failed mutation must not reconcile as if it had succeeded.
      expect(container.read(productsControllerProvider).items, hasLength(1));
    });
  });

  group('import completion reconciles the import HISTORY', () {
    test('confirm itself triggers a jobs re-read', () async {
      // Proves the wiring: the history refresh is not merely left to whichever
      // screen the shopkeeper opens next.
      final importRepo = FakeImportRepo(
        onUpload: staged(),
        onConfirm: const ImportConfirmResult(processed: 10, failed: 0),
        allJobs: [stagedJob],
      );
      final productRepo = FakeProductRepo(items: [row(1)]);
      final container =
          makeContainer(importRepo: importRepo, productRepo: productRepo);

      final importState = container.read(importControllerProvider.notifier);
      await importState.pickAndUpload();
      final before = importRepo.requestedJobOffsets.length;

      await importState.confirm();
      await Future<void>.delayed(Duration.zero);

      expect(importRepo.requestedJobOffsets.length, greaterThan(before),
          reason: 'confirm() must re-read the import history');
    });

    test('the history shows the finished job, not the staged one', () async {
      // The server moves the job on as the import is applied: VALIDATED ->
      // COMPLETED with the written-row counters filled in. The fake holds a
      // live reference to this list, so mutating it models the server's next
      // read exactly.
      final serverJobs = <ImportJob>[stagedJob];
      final importRepo = FakeImportRepo(
        onUpload: staged(),
        onConfirm: const ImportConfirmResult(processed: 10, failed: 0),
        allJobs: serverJobs,
      );
      final productRepo = FakeProductRepo(items: [row(1)]);
      final container =
          makeContainer(importRepo: importRepo, productRepo: productRepo);

      final importState = container.read(importControllerProvider.notifier);
      await importState.loadJobs();
      expect(container.read(importControllerProvider).jobs.single.status,
          'VALIDATED');

      await importState.pickAndUpload();
      await importState.confirm();
      await Future<void>.delayed(Duration.zero);

      serverJobs[0] = const ImportJob(
        id: 42,
        filename: 'stock.xlsx',
        status: 'COMPLETED',
        totalRows: 10,
        validRows: 10,
        errorRows: 0,
        processedRows: 10,
      );

      // What the Import History screen does on entry — and what confirm()
      // already triggered — must show the finished job.
      await importState.loadJobs();

      final jobs = container.read(importControllerProvider).jobs;
      expect(jobs.single.status, 'COMPLETED');
      expect(jobs.single.processedRows, 10);
      expect(container.read(importControllerProvider).jobsTotal, 1);
    });
  });
}


