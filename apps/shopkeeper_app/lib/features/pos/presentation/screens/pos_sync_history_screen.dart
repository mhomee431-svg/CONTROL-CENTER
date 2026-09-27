import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/pos_models.dart';
import '../controllers/pos_controller.dart';
import '../widgets/pos_shared.dart';

/// How the history list can be narrowed. The values are the server's own job
/// statuses — nothing is derived client-side.
enum PosHistoryFilter { all, inFlight, completed, failed }

/// Sync History — every sync job the connector has run, newest first, with the
/// server's own outcome per job and a detail sheet per row.
class PosSyncHistoryScreen extends ConsumerStatefulWidget {
  const PosSyncHistoryScreen({super.key});

  @override
  ConsumerState<PosSyncHistoryScreen> createState() =>
      _PosSyncHistoryScreenState();
}

class _PosSyncHistoryScreenState extends ConsumerState<PosSyncHistoryScreen> {
  PosHistoryFilter _filter = PosHistoryFilter.all;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      // Cold start (deep link) → load the connector; warm start → refresh only
      // the job list so the screen never flashes back to a spinner.
      if (ref.read(posControllerProvider).integration == null) {
        ref.read(posControllerProvider.notifier).load();
      } else {
        ref.read(posControllerProvider.notifier).refreshJobs();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hub = ref.watch(posControllerProvider);
    final integration = hub.integration;

    return Scaffold(
      appBar: AppBar(title: const Text('Sync history')),
      body: SafeArea(
        child: PosAsyncBody(
          status: hub.status,
          message: hub.message,
          noShopBody: 'Choose a shop to see its sync history.',
          onRetry: () => ref.read(posControllerProvider.notifier).refreshJobs(),
          builder: (context) {
            if (integration == null) {
              return PosMessageView(
                icon: Icons.point_of_sale_outlined,
                title: 'No connector yet',
                body: 'Connect a POS and run a sync to build a history.',
                action: FilledButton.icon(
                  key: const Key('pos-history-go-setup'),
                  onPressed: () => context.push(Routes.posConnectionSetup),
                  icon: const Icon(Icons.link),
                  label: const Text('Go to connection setup'),
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () =>
                  ref.read(posControllerProvider.notifier).refreshJobs(),
              child: _HistoryList(
                integration: integration,
                jobs: hub.jobs,
                filter: _filter,
                onFilterChanged: (f) => setState(() => _filter = f),
                onRefresh: () =>
                    ref.read(posControllerProvider.notifier).refreshJobs(),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Filter chips + the job rows.
class _HistoryList extends ConsumerWidget {
  const _HistoryList({
    required this.integration,
    required this.jobs,
    required this.filter,
    required this.onFilterChanged,
    required this.onRefresh,
  });

  final PosIntegration integration;
  final List<PosSyncJob> jobs;
  final PosHistoryFilter filter;
  final ValueChanged<PosHistoryFilter> onFilterChanged;
  final VoidCallback onRefresh;

  List<PosSyncJob> get _visible => switch (filter) {
    PosHistoryFilter.all => jobs,
    PosHistoryFilter.inFlight => jobs
        .where((j) => j.isQueued || j.isRunning)
        .toList(growable: false),
    PosHistoryFilter.completed => jobs
        .where((j) => j.isDone && !j.isFailed)
        .toList(growable: false),
    PosHistoryFilter.failed => jobs
        .where((j) => j.isFailed)
        .toList(growable: false),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final visible = _visible;
    // Always scrollable: pull-to-refresh must fire even when the jobs fit on
    // one screen (or the filter matched nothing).
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    posStatusIcon(integration.status),
                    size: 18,
                    color: posStatusColor(integration.status, scheme),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${integration.providerName} · '
                      '${integration.syncEnabled
                          ? 'auto-sync every ${integration.syncIntervalMinutes ?? 0} min'
                          : 'auto-sync off'}',
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                  ),
                  IconButton(
                    key: const Key('pos-history-refresh'),
                    tooltip: 'Refresh',
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh, size: 20),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in PosHistoryFilter.values)
                ChoiceChip(
                  key: Key('pos-history-filter-${f.name}'),
                  label: Text(_filterLabel(f)),
                  selected: filter == f,
                  onSelected: (_) => onFilterChanged(f),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (jobs.isEmpty)
            PosMessageView(
              icon: Icons.history_outlined,
              title: 'No syncs yet',
              body: 'Run a sync and every job — queued, done or failed — shows '
                  'up here.',
              action: FilledButton.icon(
                key: const Key('pos-history-go-sync'),
                onPressed: () => context.push(Routes.posSync),
                icon: const Icon(Icons.sync),
                label: const Text('Start a sync'),
              ),
            )
          else if (visible.isEmpty)
            PosMessageView(
              icon: Icons.filter_alt_off_outlined,
              title: 'Nothing matches this filter',
              body: 'Try another status, or clear the filter.',
              action: OutlinedButton(
                key: const Key('pos-history-clear-filter'),
                onPressed: () => onFilterChanged(PosHistoryFilter.all),
                child: const Text('Show all jobs'),
              ),
            )
          else
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < visible.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _JobTile(job: visible[i]),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _filterLabel(PosHistoryFilter f) => switch (f) {
    PosHistoryFilter.all => 'All',
    PosHistoryFilter.inFlight => 'In progress',
    PosHistoryFilter.completed => 'Completed',
    PosHistoryFilter.failed => 'Failed',
  };
}

/// One history row: the server's outcome, the scope and when it ran.
class _JobTile extends ConsumerWidget {
  const _JobTile({required this.job});

  final PosSyncJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final time = job.startedAt == null ? '' : posDateTime(job.startedAt!);
    return ListTile(
      key: Key('pos-history-job-${job.id}'),
      dense: true,
      leading: Icon(
        posJobStatusIcon(job.status),
        size: 20,
        color: posJobStatusColor(job.status, scheme),
      ),
      title: Text(posJobSummary(job), style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        '${posSyncTypeLabel(job.syncType)} · ${posJobStatusLabel(job.status)}'
        '${time.isEmpty ? '' : ' · $time'}',
        style: TextStyle(fontSize: 11, color: scheme.outline),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => _showDetail(context, ref),
    );
  }

  Future<void> _showDetail(BuildContext context, WidgetRef ref) async {
    // Diagnostics live on their own endpoint: fetch them when the sheet opens,
    // never speculatively for every row in the list.
    final controller = ref.read(posControllerProvider.notifier);
    final detail = await controller.jobDetail(job.id);
    if (!context.mounted) return;
    if (detail == null) {
      final message = ref.read(posControllerProvider).message ??
          'Could not load the job details.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _JobDetailSheet(
        job: job,
        detail: detail,
        // Only a FAILED job can be retried — the backend refuses the rest.
        onRetry: job.isFailed
            ? () async {
                final retried = await controller.retryFailedJob(job.id);
                if (retried != null && sheetContext.mounted) {
                  Navigator.of(sheetContext).pop();
                }
              }
            : null,
      ),
    );
    // The sheet may have retried the job: refresh the history either way, so
    // the row the shopkeeper came from can never show a stale status.
    if (job.isFailed && context.mounted) {
      await ref.read(posControllerProvider.notifier).refreshJobs();
    }
  }
}

/// Everything the server reported about one job: the payload rows the history
/// list already shows, PLUS the diagnostics only the job-detail endpoint
/// carries (per-item logs and every recorded mapping conflict), and the retry
/// action for a job that failed.
class _JobDetailSheet extends StatelessWidget {
  const _JobDetailSheet({
    required this.job,
    this.detail,
    this.onRetry,
  });

  final PosSyncJob job;

  /// `GET /shopkeeper/pos/jobs/{id}` payload — null when the diagnostics call
  /// failed, in which case the sheet still renders the payload rows.
  final PosJobDetail? detail;

  /// Set only for a FAILED job: closing the sheet runs the retry.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A local copy so the diagnostics blocks can null-check it: `detail` is a
    // field, and Dart does not promote fields.
    final PosJobDetail? d = detail;
    final duration = posJobDuration(job);
    final rows = <(String, String)>[
      ('Job', '#${job.id}'),
      ('Status', posJobStatusLabel(job.status)),
      ('Scope', posSyncTypeLabel(job.syncType)),
      ('Trigger', job.trigger.toLowerCase()),
      ('Processed', '${job.itemsProcessed}'),
      ('Synced', '${job.itemsSucceeded}'),
      ('Failed', '${job.itemsFailed}'),
      if (job.startedAt != null) ('Started', posDateTime(job.startedAt!)),
      if (job.completedAt != null) ('Finished', posDateTime(job.completedAt!)),
      ('Took', posDurationLabel(duration)),
    ];

    return SafeArea(
      // The sheet must never clip on a short screen: a job can carry more rows
      // than the default bottom-sheet height allows.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  posJobStatusIcon(job.status),
                  color: posJobStatusColor(job.status, scheme),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sync job #${job.id}',
                    key: const Key('pos-history-detail'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (job.isFailed && (job.errorSummary?.isNotEmpty ?? false)) ...[
              Text(
                job.errorSummary!,
                style: TextStyle(fontSize: 13, color: scheme.error),
              ),
              const SizedBox(height: 12),
            ],
            for (final (label, value) in rows) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        label,
                        style: TextStyle(fontSize: 12, color: scheme.outline),
                      ),
                    ),
                    Expanded(
                      child: Text(value, style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ],
            if (d != null && d.logs.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Log', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              for (final log in d.logs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        log.isError
                            ? Icons.error_outline
                            : log.isWarning
                                ? Icons.warning_amber_outlined
                                : Icons.check_circle_outline,
                        size: 16,
                        color: log.isError
                            ? scheme.error
                            : log.isWarning
                                ? AppColors.warning
                                : scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          log.itemReference == null
                              ? log.message
                              : '${log.itemReference}: ${log.message}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (d != null && d.conflicts.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Conflicts', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              for (final conflict in d.conflicts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    [
                      if (conflict.posProductCode.isNotEmpty)
                        conflict.posProductCode,
                      if (conflict.field.isNotEmpty) conflict.field,
                      if (conflict.detail.isNotEmpty) conflict.detail,
                    ].join(' - '),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('pos-history-retry'),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry this sync'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

