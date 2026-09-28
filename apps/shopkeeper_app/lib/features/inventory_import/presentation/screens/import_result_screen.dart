import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/token_store.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/state/system_state.dart';
import '../../../../core/state/system_state_view.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../data/import_repository.dart';
import '../../domain/import_models.dart';
import '../widgets/import_report_sheet.dart';
import '../widgets/import_status_view.dart';

/// The OUTCOME of one import job, addressable on its own.
///
/// Import history is a list, and a notification about a failed or partial
/// import used to drop the shopkeeper into that whole list with no way to see
/// the job it was actually about. This screen is the deep-linkable target: the
/// backend already sends `hyperlocal://shopkeeper/imports/{job_id}` plus a
/// `job_id` payload, and [Routes.importResult] is where that id lands — so a
/// future notification opens the exact feature instead of a list to re-scan.
///
/// The job is FETCHED, never taken from the notification. A push payload is a
/// hint that can be stale, forged, or simply wrong about a job that no longer
/// exists, so this screen re-reads the real record and renders that.
class ImportResultScreen extends ConsumerStatefulWidget {
  const ImportResultScreen({required this.jobId, super.key});

  /// The job to show. Validated at the call site
  /// ([ShopkeeperNotification.payloadInt] only yields a positive int), so only
  /// a real id reaches this constructor.
  final int jobId;

  @override
  ConsumerState<ImportResultScreen> createState() => _ImportResultScreenState();
}

class _ImportResultScreenState extends ConsumerState<ImportResultScreen> {
  /// Held in a field rather than a `late final` so Retry can start a NEW
  /// request — a final future can only ever be awaited once.
  Future<ImportJob>? _job;

  @override
  void initState() {
    super.initState();
    _job = _load();
  }

  Future<ImportJob> _load() async {
    final shopId = ref.read(selectedShopProvider)?.id;
    if (shopId == null) {
      throw const ApiException(message: 'No shop selected');
    }
    final token = await ref.read(tokenStoreProvider).readAccessToken();
    if (token == null) {
      throw const ApiException(message: 'Not signed in');
    }
    // `preview` is the per-job read: it returns the job (status + counters) and
    // the row-level report, so one call answers both this screen and the report
    // sheet its action opens.
    final preview = await ref
        .read(inventoryImportRepositoryProvider)
        .preview(shopId, widget.jobId, token);
    return preview.meta;
  }

  Future<void> _openReport(ImportJob job) async {
    final shopId = ref.read(selectedShopProvider)?.id;
    if (shopId == null) return;
    final token = await ref.read(tokenStoreProvider).readAccessToken();
    if (token == null || !mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => ImportReportSheet(
        job: job,
        future: ref
            .read(inventoryImportRepositoryProvider)
            .preview(shopId, job.id, token),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import result')),
      body: SafeArea(
        child: FutureBuilder<ImportJob>(
          future: _job,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                key: Key('import-result-loading'),
                child: CircularProgressIndicator(),
              );
            }
            if (snapshot.hasError) {
              // A deleted job, an expired session or an offline device is
              // EXPLAINED, with a way out — never a blank screen. Import
              // history is the fallback because it can still show what
              // happened even when this one job cannot be opened.
              final error = snapshot.error;
              return SystemStateView(
                spec: SystemStateSpec.resolve(
                  state: error is ApiException ? error.systemState : null,
                  title: 'Could not open this import',
                  fallbackMessage: 'This import is no longer available.',
                ),
                onRetry: () => setState(() => _job = _load()),
                secondary: TextButton(
                  key: const Key('import-result-error-history'),
                  onPressed: () => context.go(Routes.importHistory),
                  child: const Text('Open import history'),
                ),
              );
            }

            final job = snapshot.data!;
            // The SAME component the post-confirm result renders through, so a
            // job reached from a notification looks exactly like the one the
            // shopkeeper watched finish.
            final showReport = job.processedRows > 0 || job.failedRows > 0;

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ImportStatusView(
                      tone: importStatusTone(job.status),
                      title: job.statusLabel,
                      message: job.filename,
                      titleKey: const Key('import-result-title'),
                    ),
                    if (job.hasErrors) ...[
                      const SizedBox(height: 20),
                      Text(
                        '${job.errorRows} row(s) could not be imported.',
                        key: const Key('import-result-errors'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (showReport)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const Key('import-result-view-report'),
                          onPressed: () => _openReport(job),
                          icon: const Icon(Icons.fact_check_outlined),
                          label: const Text('View row report'),
                        ),
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        key: const Key('import-result-history'),
                        onPressed: () => context.go(Routes.importHistory),
                        child: const Text('View import history'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}