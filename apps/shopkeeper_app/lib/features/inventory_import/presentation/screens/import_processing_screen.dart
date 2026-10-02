import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/network/token_store.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../controllers/import_controller.dart';
import '../widgets/import_report_sheet.dart';
import '../widgets/import_status_view.dart';
import '../../data/import_repository.dart';
import '../../domain/import_models.dart';

/// Import Processing — the confirm step: applies the staged job to inventory
/// and renders the outcome (Import Success / Partial Success / Import Failed
/// / queued background processing).
///
/// The screen fires `confirm()` ONCE on entry, watching the shared
/// [importControllerProvider] for the result.
class ImportProcessingScreen extends ConsumerStatefulWidget {
  const ImportProcessingScreen({super.key});

  @override
  ConsumerState<ImportProcessingScreen> createState() =>
      _ImportProcessingScreenState();
}

class _ImportProcessingScreenState
    extends ConsumerState<ImportProcessingScreen> {
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (_fired) return;
      final state = ref.read(importControllerProvider);
      if (state.status == ImportStatus.preview &&
          state.preview != null &&
          state.preview!.validCount > 0) {
        _fired = true;
        ref.read(importControllerProvider.notifier).confirm();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(importControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(appText(context).commonApplyingImport)),
      body: SafeArea(
        child: switch (state.status) {
          ImportStatus.confirming => const _ProcessingView(),
          ImportStatus.done => _ResultView(result: state.result!),
          ImportStatus.error => _FailedRetryView(
              message: state.message ?? 'Could not apply the import.',
              onRetry: () {
                _fired = true;
                ref.read(importControllerProvider.notifier).confirm();
              },
            ),
          // Arrived without a staged preview → nothing to confirm.
          _ => const _NothingToApplyView(),
        },
      ),
    );
  }
}

class _ProcessingView extends StatelessWidget {
  const _ProcessingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(appText(context).importProcessingScreenApplyingRowsToYourInventory,
              key: const Key('import-processing'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            appText(context).importProcessingScreenThisUsuallyTakesAFew,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultView extends ConsumerWidget {
  const _ResultView({required this.result});

  final ImportConfirmResult result;

  /// The status this confirm result represents, in the SHARED vocabulary.
  ///
  /// Derived once and used for both the copy and the visuals, so the headline
  /// and the icon can never describe different outcomes. Zero rows applied is a
  /// FAILURE even when the payload also reports zero failures — the rows were
  /// not imported, and saying "Completed" would be a lie.
  String get _status => result.queued
      ? ImportJobStatusValue.queued
      : result.processed == 0
          ? ImportJobStatusValue.failed
          : (result.failed > 0
              ? ImportJobStatusValue.partial
              : ImportJobStatusValue.completed);

  /// Headline + one-line detail for [_status]. Copy only — the icon and colour
  /// come from the shared [importStatusTone].
  (String, String, String) get _copy => switch (_status) {
        ImportJobStatusValue.queued => (
            'Import queued',
            '${result.processed} rows queued for background processing. '
                'Check Import history for the outcome.',
            'import-result-queued',
          ),
        ImportJobStatusValue.failed => (
            'Import failed',
            'No rows could be applied. Check Import history for details.',
            'import-result-failed',
          ),
        ImportJobStatusValue.partial => (
            'Partially imported',
            '${result.processed + result.failed} rows processed — '
                '${result.processed} successful, ${result.failed} failed.',
            'import-result-partial',
          ),
        _ => (
            'Import successful',
            '${result.processed} rows processed — all successful.',
            'import-result-success',
          ),
      };

  /// True when rows were applied, so a per-row report exists to open.
  bool get _showResults => !result.queued && result.processed > 0;

  /// True when rows failed and are worth inspecting.
  bool get _showErrors => result.failed > 0;

  /// Header stub for the report sheet — the confirm payload carries counts, not
  /// the workbook name, so the sheet is titled by job id instead of guessing.
  ImportJob get _reportJob {
    return ImportJob(
      id: result.jobId ?? 0,
      filename: 'Import #${result.jobId ?? '—'}',
      // The SAME status the headline and icon are drawn from, so the report
      // sheet can never contradict the result the shopkeeper is looking at.
      status: _status,
      totalRows: result.processed + result.failed,
      validRows: result.processed,
      errorRows: result.failed,
      processedRows: result.processed,
      failedRows: result.failed,
    );
  }

  /// Opens this job's row-level report, optionally filtered to failures.
  /// Does nothing when the payload carried no job id (nothing to fetch).
  Future<void> _openReport(
    BuildContext context,
    WidgetRef ref, {
    required ReportFilter filter,
  }) async {
    final shopId = ref.read(selectedShopProvider)?.id;
    final jobId = result.jobId;
    if (shopId == null || jobId == null) return;
    final token = await ref.read(tokenStoreProvider).readAccessToken();
    if (token == null || !context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => ImportReportSheet(
        job: _reportJob,
        future: ref
            .read(inventoryImportRepositoryProvider)
            .preview(shopId, jobId, token),
        initialFilter: filter,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (title, detail, keyName) = _copy;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The SAME component the deep-linked Import result screen and the
            // history list use for their status visuals.
            ImportStatusView(
              tone: importStatusTone(_status),
              title: title,
              message: detail,
              titleKey: Key(keyName),
            ),
            const SizedBox(height: 24),
            // Partial failures are never hidden — the shopkeeper can open the
            // applied rows and the failed rows separately from here.
            if (_showResults) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('import-result-view-results'),
                  onPressed: () =>
                      _openReport(context, ref, filter: ReportFilter.all),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(appText(context).commonViewResults),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_showErrors) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('import-result-view-errors'),
                  onPressed: () =>
                      _openReport(context, ref, filter: ReportFilter.errors),
                  icon: const Icon(Icons.error_outline),
                  label: Text(appText(context).importProcessingScreenViewErrorsFailed(result.failed)),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (result.queued) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  key: const Key('import-result-history'),
                  onPressed: () {
                    ref.read(importControllerProvider.notifier).resetFlow();
                    context.go(Routes.importHistory);
                  },
                  child: Text(appText(context).commonViewImportHistory),
                ),
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('import-result-done'),
                onPressed: () {
                  ref.read(importControllerProvider.notifier).resetFlow();
                  context.go(Routes.importCenter);
                },
                child: Text(appText(context).commonDone),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailedRetryView extends ConsumerWidget {
  const _FailedRetryView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: AppTheme.rejectedRed),
            const SizedBox(height: 16),
            Text(
              appText(context).commonImportFailed,
              key: const Key('import-result-failed'),
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('import-failed-back'),
                    onPressed: () {
                      ref.read(importControllerProvider.notifier).resetFlow();
                      context.go(Routes.importCenter);
                    },
                    child: Text(appText(context).commonBack3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const Key('import-failed-retry'),
                    onPressed: onRetry,
                    child: Text(appText(context).commonRetry2),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NothingToApplyView extends ConsumerWidget {
  const _NothingToApplyView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_off_outlined,
              size: 40, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(appText(context).commonNothingToApply),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('import-nothing-back'),
            onPressed: () {
              ref.read(importControllerProvider.notifier).resetFlow();
              context.go(Routes.importCenter);
            },
            child: Text(appText(context).commonBackToImportCenter2),
          ),
        ],
      ),
    );
  }
}
