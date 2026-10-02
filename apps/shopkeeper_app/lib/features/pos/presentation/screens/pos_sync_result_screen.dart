import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/pos_models.dart';
import '../controllers/pos_controller.dart';
import '../widgets/pos_shared.dart';

/// Sync Result — the outcome of one sync, straight from the server's counters.
class PosSyncResultScreen extends ConsumerWidget {
  const PosSyncResultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(posSyncFlowProvider);

    return Scaffold(
      appBar: AppBar(title: Text(appText(context).commonSyncResult)),
      body: SafeArea(
        child: PosSyncResultView(
          job: flow.job,
          integration: flow.integration,
        ),
      ),
    );
  }
}

/// The outcome itself, reusable by the Result screen and (when the app renders
/// standalone) by the Progress screen.
class PosSyncResultView extends ConsumerWidget {
  const PosSyncResultView({super.key, this.job, this.integration});

  final PosSyncJob? job;
  final PosIntegration? integration;

  bool get _partial {
    final j = job;
    if (j == null) return false;
    return !j.isFailed &&
        !j.isQueued &&
        !j.isRunning &&
        (j.itemsFailed > 0 || j.status == 'COMPLETED_WITH_ERRORS');
  }

  IconData get _icon {
    final j = job;
    if (j == null) return Icons.help_outline;
    if (j.isFailed) return Icons.error_outline;
    if (j.isQueued || j.isRunning) return Icons.schedule;
    if (_partial) return Icons.warning_amber_outlined;
    return Icons.check_circle_outline;
  }

  Color _color(ColorScheme scheme) {
    final j = job;
    if (j == null) return scheme.outline;
    if (j.isFailed) return scheme.error;
    if (j.isQueued || j.isRunning || _partial) return AppTheme.pendingAmber;
    return AppTheme.verifiedGreen;
  }

  String get _title {
    final j = job;
    if (j == null) return 'No sync to report';
    if (j.isFailed) return 'Sync failed';
    if (j.isQueued || j.isRunning) return 'Sync still in flight';
    if (_partial) return 'Synced with errors';
    return 'Sync complete';
  }

  String? get _detail {
    final j = job;
    if (j == null) return null;
    if (j.isFailed) {
      return j.errorSummary ?? 'The connector did not report what went wrong.';
    }
    if (j.isQueued || j.isRunning) return posJobSummary(j);
    final duration = posJobDuration(j);
    return '${posJobSummary(j)}'
        '${duration == null ? '' : ' · took ${posDurationLabel(duration)}'}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final color = _color(scheme);
    final detail = _detail;
    final settled = job != null && (job!.isDone || job!.isFailed);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_icon, size: 56, color: color),
            const SizedBox(height: 16),
            Text(
              _title,
              key: const Key('pos-sync-result-title'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(
                detail,
                key: const Key('pos-sync-result-detail'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: scheme.outline),
              ),
            ],
            if (job != null && !job!.isFailed) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ResultCounter(
                    key: const Key('pos-result-synced'),
                    label: appText(context).commonSynced2,
                    value: job!.itemsSucceeded,
                    color: AppTheme.verifiedGreen,
                  ),
                  _ResultCounter(
                    key: const Key('pos-result-failed'),
                    label: appText(context).commonFailed3,
                    value: job!.itemsFailed,
                    color: scheme.error,
                  ),
                ],
              ),
            ],
            if (integration != null && settled) ...[
              const SizedBox(height: 16),
              Text(
                '${integration!.providerName} · '
                'last sync '
                '${integration!.lastSyncAt == null
                    ? '—'
                    : posDateTime(integration!.lastSyncAt!)}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
            ],
            const SizedBox(height: 24),
            _ResultActions(settled: settled),
          ],
        ),
      ),
    );
  }
}

/// The outcome actions: Done (back to the hub), Sync again, View history.
/// "Sync again" only makes sense once the job has settled.
class _ResultActions extends ConsumerWidget {
  const _ResultActions({required this.settled});

  final bool settled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void resetAndThen(void Function() go) {
      ref.read(posSyncFlowProvider.notifier).reset();
      go();
    }

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('pos-result-done'),
            onPressed: () =>
                resetAndThen(() => GoRouter.maybeOf(context)?.go(Routes.pos)),
            child: Text(appText(context).commonDone2),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('pos-result-again'),
                onPressed: settled
                    ? () => resetAndThen(
                        () => GoRouter.maybeOf(context)?.push(Routes.posSync),
                      )
                    : null,
                child: Text(appText(context).commonSyncAgain),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: const Key('pos-result-history'),
                onPressed: () => resetAndThen(
                  () => GoRouter.maybeOf(context)?.push(Routes.posSyncHistory),
                ),
                child: Text(appText(context).commonViewHistory2),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One outcome counter.
class _ResultCounter extends StatelessWidget {
  const _ResultCounter({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          appText(context).posSyncResultScreenValue(value),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}
