import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/network/token_store.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../data/import_repository.dart';
import '../../domain/import_models.dart';
import '../controllers/import_controller.dart';

/// Import History — every past import job for the shop with its status and
/// row outcomes. Tapping a job fetches its full row-level report in a sheet:
/// valid rows, plus validation/processing errors.
class ImportHistoryScreen extends ConsumerStatefulWidget {
  const ImportHistoryScreen({super.key});

  @override
  ConsumerState<ImportHistoryScreen> createState() =>
      _ImportHistoryScreenState();
}

class _ImportHistoryScreenState extends ConsumerState<ImportHistoryScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(importControllerProvider.notifier).loadJobs(),
    );
  }

  Future<void> _openJob(ImportJob job) async {
    final shopId = ref.read(selectedShopProvider)?.id;
    if (shopId == null) return;
    final token = await ref.read(tokenStoreProvider).readAccessToken();
    if (!mounted || token == null) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _JobDetailsSheet(
        job: job,
        future: ref
            .read(inventoryImportRepositoryProvider)
            .preview(shopId, job.id, token),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(importControllerProvider);
    final jobs = state.jobs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import history'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_outlined),
            onPressed: () =>
                ref.read(importControllerProvider.notifier).loadJobs(),
          ),
        ],
      ),
      body: jobs.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history_outlined,
                        size: 40,
                        color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 12),
                    const Text('No imports yet'),
                    const SizedBox(height: 4),
                    Text(
                      'Excel files you upload will appear here with their '
                      'row-level outcomes.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: jobs.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _JobTile(
                job: jobs[i],
                onTap: () => _openJob(jobs[i]),
              ),
            ),
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job, required this.onTap});

  final ImportJob job;
  final VoidCallback onTap;

  (IconData, Color) get _statusView => switch (job.status) {
        'COMPLETED' => (Icons.check_circle, AppTheme.verifiedGreen),
        'VALIDATED' => (Icons.fact_check_outlined, AppTheme.verifiedGreen),
        'PARTIAL' => (Icons.warning_amber_outlined, AppTheme.pendingAmber),
        'FAILED' => (Icons.error_outline, AppTheme.rejectedRed),
        'PROCESSING' => (Icons.sync, AppTheme.pendingAmber),
        _ => (Icons.schedule, AppTheme.suspendedGrey),
      };

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _statusView;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color, size: 24),
      title: Text(
        job.filename,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${job.status.replaceAll('_', ' ')} · '
        '${job.totalRows} rows · ${job.validRows} valid, ${job.errorRows} errors',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// Bottom sheet with the job's full row-level report.
class _JobDetailsSheet extends StatelessWidget {
  const _JobDetailsSheet({required this.job, required this.future});

  final ImportJob job;
  final Future<ImportPreview> future;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: FutureBuilder<ImportPreview>(
          future: future,
          builder: (context, snap) {
            final header = Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.filename,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${job.status.replaceAll('_', ' ')} · '
                    '${job.totalRows} rows · ${job.validRows} valid, '
                    '${job.errorRows} errors',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            );

            if (snap.connectionState != ConnectionState.done) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    header,
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  ],
                ),
              );
            }

            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    header,
                    Text(
                      'Could not load the report for this import.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ),
              );
            }

            final rows = snap.data?.rows ?? const <ImportRow>[];
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                header,
                Flexible(
                  child: rows.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No row-level details recorded for this import.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          itemCount: rows.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final row = rows[i];
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                row.isError
                                    ? Icons.error_outline
                                    : Icons.check_circle_outline,
                                color: row.isError
                                    ? AppTheme.rejectedRed
                                    : AppTheme.verifiedGreen,
                                size: 18,
                              ),
                              title: Text(
                                'Row ${row.rowNumber}'
                                '${row.productName == null ? '' : ' · ${row.productName}'}',
                                style: const TextStyle(fontSize: 13),
                              ),
                              subtitle: row.isError
                                  ? Text(
                                      '${row.errorCode ?? 'ERROR'} — '
                                      '${row.errorMessage ?? 'Invalid row'}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                      ),
                                    )
                                  : const Text('Valid',
                                      style: TextStyle(fontSize: 12)),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
