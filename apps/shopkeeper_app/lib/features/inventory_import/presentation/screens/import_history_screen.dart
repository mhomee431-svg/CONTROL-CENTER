import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/network/token_store.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/ui/lazy_list.dart';
import '../../../../core/ui/load_more.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../data/import_repository.dart';
import '../../domain/import_models.dart';
import '../controllers/import_controller.dart';
import '../widgets/import_status_view.dart';
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
    final total = ref.watch(importControllerProvider.select((s) => s.jobsTotal));
    final loadingMore =
        ref.watch(importControllerProvider.select((s) => s.loadingMoreJobs));
    final hasMore = jobs.length < total;

    return Scaffold(
      appBar: AppBar(
        title: Text(appText(context).commonImportHistory),
        actions: [
          IconButton(
            tooltip: appText(context).commonRefresh5,
            icon: const Icon(Icons.refresh_outlined),
            onPressed: () =>
                ref.read(importControllerProvider.notifier).loadJobs(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(importControllerProvider.notifier).loadJobs(),
        child: LazyListView(
          // The history is PAGED BY THE BACKEND (`limit`/`offset`): only the
          // jobs already fetched are rendered, and the footer reveals the next
          // page. `total` is the server's own count, so "Load more" appears
          // exactly when further jobs exist.
          // Always scrollable: pull-to-refresh works even with a single job,
          // and the empty state IS the list, so it can be pulled too.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: jobs.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) =>
              _JobTile(job: jobs[i], onTap: () => _openJob(jobs[i])),
          footer: [
            if (hasMore)
              LoadMoreTile(
                key: const Key('import-history-load-more'),
                hidden: total - jobs.length,
                onTap: loadingMore
                    ? () {}
                    : () => ref
                        .read(importControllerProvider.notifier)
                        .loadMoreJobs(),
              ),
            if (loadingMore)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
          ],
          emptyPlaceholder: const _EmptyHistory(),
        ),
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
            Text(appText(context).commonNoImportsYet),
            const SizedBox(height: 4),
            Text(
              appText(context).importHistoryScreenExcelFilesYouUploadWill,
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

  /// Icon + colour for this job, from the SHARED tone map.
  ///
  /// This used to be a second, private status→(icon, colour) switch that had
  /// already drifted from the result screen's: it drew a GREEN TICK for
  /// `VALIDATED` while the chip beside it read "Validating" in amber, because
  /// [ImportJobStatusValue.label] treats that legacy status as still-validating.
  /// One vocabulary now decides both the icon and the colour, so a row can no
  /// longer contradict its own label.
  ImportStatusTone get _tone => importStatusTone(job.status);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = _tone;
    final date = job.importDate;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(tone.icon, color: tone.color, size: 24),
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
                      _StatusChip(label: job.statusLabel, color: tone.color),
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
                    appText(context).importHistoryScreenRowsTotalRowsSuccessSuccessRowsFailed(job.totalRows, job.successRows, job.failedRowCount),
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
        borderRadius: AppRadius.smBorder,
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
