import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
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
            return _HistoryList(
              integration: integration,
              jobs: hub.jobs,
              filter: _filter,
              onFilterChanged: (f) => setState(() => _filter = f),
              onRefresh: () =>
                  ref.read(posControllerProvider.notifier).refreshJobs(),
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
    return SingleChildScrollView(
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
      onTap: () => _showDetail(context),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _JobDetailSheet(job: job),
    );
  }
}

/// Everything the server reported about one job.
class _JobDetailSheet extends StatelessWidget {
  const _JobDetailSheet({required this.job});

  final PosSyncJob job;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
          ],
        ),
      ),
    );
  }
}

