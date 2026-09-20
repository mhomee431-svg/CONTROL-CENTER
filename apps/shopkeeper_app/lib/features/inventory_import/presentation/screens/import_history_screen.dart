import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/token_store.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../data/import_repository.dart';
import '../../domain/import_models.dart';
import '../controllers/import_controller.dart';
import '../widgets/import_report_sheet.dart';

/// Import History — every past import job for the shop with its date, row
/// counts and status. Tapping a job opens its full row-level report.
///
/// Statuses and counters are the API's ([ImportJobStatusValue] +
/// `processed_rows` / `failed_rows`); the screen never invents a state or a
/// number the backend cannot return.
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
    final jobs = ref.watch(importControllerProvider.select((s) => s.jobs));

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
          ? const _EmptyHistory()
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: jobs.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) =>
                  _JobTile(job: jobs[i], onTap: () => _openJob(jobs[i])),
            ),
    );
  }
}
/// Nothing imported yet — explains what will appear here.
class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.outline,
            ),
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
    );
  }
}

/// One past import: date, file, row counts (rows / success / failed) and status.
class _JobTile extends StatelessWidget {
  const _JobTile({required this.job, required this.onTap});

  final ImportJob job;
  final VoidCallback onTap;

  (IconData, Color) get _statusView => switch (job.status) {
    ImportJobStatusValue.completed || ImportJobStatusValue.validated => (
      Icons.check_circle,
      AppTheme.verifiedGreen,
    ),
    ImportJobStatusValue.partial => (
      Icons.warning_amber_outlined,
      AppTheme.pendingAmber,
    ),
    ImportJobStatusValue.failed => (Icons.error_outline, AppTheme.rejectedRed),
    ImportJobStatusValue.processing || ImportJobStatusValue.queued => (
      Icons.sync,
      AppTheme.pendingAmber,
    ),
    _ => (Icons.schedule, AppTheme.suspendedGrey),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = _statusView;
    final date = job.importDate;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          job.filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusChip(label: job.statusLabel, color: color),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.event_outlined,
                        size: 13,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        date == null
                            ? 'Date unavailable'
                            : _formatImportDate(date),
                        key: const Key('import-job-date'),
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Rows ${job.totalRows} · Success ${job.successRows} · '
                    'Failed ${job.failedRowCount}',
                    key: const Key('import-job-metrics'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

/// "18 Sep 2026, 09:19 PM" — local time, one formatter for the whole screen.
String _formatImportDate(DateTime value) =>
    DateFormat('d MMM yyyy, hh:mm a').format(value);

/// Compact status pill tinted by the job's outcome colour.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}