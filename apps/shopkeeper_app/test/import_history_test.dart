import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/data/import_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/domain/import_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/presentation/screens/import_history_screen.dart';

import 'fakes.dart';

/// Import History suite — the status vocabulary, the model's date/counter
/// mapping and the list tile that surfaces them.
void main() {
  group('ImportJobStatusValue', () {
    test('labels every status the backend can return', () {
      expect(ImportJobStatusValue.label('VALIDATING'), 'Validating');
      expect(ImportJobStatusValue.label('AWAITING_CONFIRMATION'), 'Uploaded');
      expect(ImportJobStatusValue.label('QUEUED'), 'Processing');
      expect(ImportJobStatusValue.label('PROCESSING'), 'Processing');
      expect(ImportJobStatusValue.label('COMPLETED'), 'Completed');
      expect(ImportJobStatusValue.label('PARTIAL'), 'Partial Success');
      expect(ImportJobStatusValue.label('FAILED'), 'Failed');
    });

    test('never crashes on an unrecognised server status', () {
      expect(ImportJobStatusValue.label('SOME_FUTURE_STATE'), 'Some future state');
      expect(ImportJobStatusValue.label(''), 'Unknown');
    });

    test('in-flight and has-outcome partition the lifecycle', () {
      for (final s in const [
        'VALIDATING',
        'AWAITING_CONFIRMATION',
        'QUEUED',
        'PROCESSING',
      ]) {
        expect(ImportJobStatusValue.isInFlight(s), isTrue, reason: s);
      }
      expect(ImportJobStatusValue.isInFlight('COMPLETED'), isFalse);
      expect(ImportJobStatusValue.isInFlight('FAILED'), isFalse);

      expect(ImportJobStatusValue.hasOutcome('COMPLETED'), isTrue);
      expect(ImportJobStatusValue.hasOutcome('PARTIAL'), isTrue);
      // A staged job has no applied rows yet.
      expect(ImportJobStatusValue.hasOutcome('AWAITING_CONFIRMATION'), isFalse);
      expect(ImportJobStatusValue.hasOutcome('VALIDATING'), isFalse);
    });
  });

  group('ImportJob.fromJson', () {
    test('parses timestamps, status and both counter pairs', () {
      final job = ImportJob.fromJson(const {
        'id': 42,
        'filename': 'stock.xlsx',
        'status': 'PARTIAL',
        'total_rows': 500,
        'valid_rows': 482,
        'error_rows': 18,
        'processed_rows': 482,
        'failed_rows': 18,
        'created_at': '2026-09-18T15:49:00Z',
        'started_at': '2026-09-18T15:49:30Z',
        'completed_at': '2026-09-18T15:50:10Z',
      });

      expect(job.id, 42);
      expect(job.statusLabel, 'Partial Success');
      expect(job.processedRows, 482);
      expect(job.failedRows, 18);
      expect(job.createdAt?.toUtc(), DateTime.utc(2026, 9, 18, 15, 49));
      expect(job.startedAt?.toUtc(), DateTime.utc(2026, 9, 18, 15, 49, 30));
      expect(job.completedAt?.toUtc(), DateTime.utc(2026, 9, 18, 15, 50, 10));
    });

    test('importDate falls back to created_at for an unconfirmed upload', () {
      // started_at stays null until processing begins, so the history list
      // must not lose the date for a staged upload.
      final staged = ImportJob.fromJson(const {
        'id': 1,
        'status': 'AWAITING_CONFIRMATION',
        'created_at': '2026-09-18T15:49:00Z',
      });
      expect(staged.startedAt, isNull);
      expect(staged.importDate?.toUtc(), DateTime.utc(2026, 9, 18, 15, 49));
    });

    test('a missing date degrades to null instead of throwing', () {
      final job = ImportJob.fromJson(const {
        'id': 1,
        'status': 'COMPLETED',
        'created_at': 'not-a-timestamp',
      });
      expect(job.createdAt, isNull);
      expect(job.importDate, isNull);
    });

    test('success/failed follow the job phase', () {
      // Applied job → processing counters (the real outcome).
      const applied = ImportJob(
        id: 1,
        filename: 'a.xlsx',
        status: 'PARTIAL',
        totalRows: 500,
        validRows: 482,
        errorRows: 18,
        processedRows: 482,
        failedRows: 18,
      );
      expect(applied.successRows, 482);
      expect(applied.failedRowCount, 18);

      // Staged job → validation counters (nothing applied yet).
      const staged = ImportJob(
        id: 2,
        filename: 'b.xlsx',
        status: 'AWAITING_CONFIRMATION',
        totalRows: 10,
        validRows: 8,
        errorRows: 2,
      );
      expect(staged.successRows, 8);
      expect(staged.failedRowCount, 2);
    });
  });

  group('ImportHistoryScreen', () {
    testWidgets('shows date, row counts and shopkeeper status copy', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          inventoryImportRepositoryProvider.overrideWithValue(
            FakeImportRepo(
              onList: [
                ImportJob(
                  id: 7,
                  filename: 'march.xlsx',
                  status: 'PARTIAL',
                  totalRows: 500,
                  validRows: 482,
                  errorRows: 18,
                  processedRows: 482,
                  failedRows: 18,
                  // Fixed local time → the rendered date is timezone-stable.
                  createdAt: DateTime(2026, 9, 18, 21, 19),
                ),
              ],
            ),
          ),
          tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token'),
          ),
          selectedShopProvider.overrideWith(
            () => SelectedShopOverride(ownerShop()),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ImportHistoryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('march.xlsx'), findsOneWidget);
      // Date — from created_at, which staged uploads also carry.
      expect(find.text('18 Sep 2026, 09:19 PM'), findsOneWidget);
      // Rows / Success / Failed.
      expect(
        find.text('Rows 500 · Success 482 · Failed 18'),
        findsOneWidget,
      );
      // Status — friendly copy, never the raw enum.
      expect(find.text('Partial Success'), findsOneWidget);
      expect(find.text('PARTIAL'), findsNothing);
    });

    testWidgets('empty state explains what will appear here', (tester) async {
      final container = ProviderContainer(
        overrides: [
          inventoryImportRepositoryProvider.overrideWithValue(
            FakeImportRepo(onList: const []),
          ),
          tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token'),
          ),
          selectedShopProvider.overrideWith(
            () => SelectedShopOverride(ownerShop()),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ImportHistoryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No imports yet'), findsOneWidget);
    });
  });
}