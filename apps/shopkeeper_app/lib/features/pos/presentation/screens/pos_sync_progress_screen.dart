import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../products/presentation/controllers/products_controller.dart';
import '../controllers/pos_controller.dart';
import '../widgets/pos_shared.dart';
import 'pos_sync_result_screen.dart';

/// Sync Progress — follows the queued job on the SERVER until it reports an
/// outcome, then hands off to the Sync Result screen.
///
/// The screen owns the timer (a `Timer.periodic` on the injectable
/// [posSyncPollIntervalProvider]); the controller owns the state. The timer
/// stops the moment the job reaches a terminal state — or at the poll cap, so a
/// provider that never finishes cannot spin forever.
class PosSyncProgressScreen extends ConsumerStatefulWidget {
  const PosSyncProgressScreen({super.key});

  @override
  ConsumerState<PosSyncProgressScreen> createState() =>
      _PosSyncProgressScreenState();
}

class _PosSyncProgressScreenState
    extends ConsumerState<PosSyncProgressScreen> {
  Timer? _timer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final flow = ref.read(posSyncFlowProvider);
      // Opened without a queued job (deep link / cold start) → queue one now.
      if (flow.phase == PosSyncPhase.idle ||
          flow.phase == PosSyncPhase.error) {
        await ref.read(posSyncFlowProvider.notifier).start();
      }
      _restartTimer();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(ref.read(posSyncPollIntervalProvider), (_) {
      final flow = ref.read(posSyncFlowProvider);
      if (flow.phase != PosSyncPhase.running ||
          flow.polls >= kPosSyncMaxPolls) {
        _timer?.cancel();
        return;
      }
      ref.read(posSyncFlowProvider.notifier).poll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(posSyncFlowProvider);

    // Follow the job to its outcome — once.
    ref.listen<PosSyncFlowState>(posSyncFlowProvider, (prev, next) {
      if (next.phase == PosSyncPhase.done || next.phase == PosSyncPhase.error) {
        _timer?.cancel();
      }
      if (next.phase == PosSyncPhase.done && !_navigated) {
        _navigated = true;
        // DATA CONSISTENCY: a completed sync wrote products + stock
        // server-side, so the mounted catalog is now stale. Same reason as
        // the Excel import: the app is a StatefulShellBranch, so the Products
        // tab never re-runs initState on the way back to it.
        //
        // This fires on the JOB's terminal state, not when it was queued, so
        // the refetch cannot race a still-running sync. `refresh()` is
        // silent: a failure here must not disturb the result screen.
        unawaited(
          ref.read(productsControllerProvider.notifier).refresh(),
        );
        // Standalone (no router) stays here and renders the result inline.
        GoRouter.maybeOf(context)?.pushReplacement(Routes.posSyncResult);
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Sync progress')),
      body: SafeArea(
        child: switch (flow.phase) {
          PosSyncPhase.idle || PosSyncPhase.starting => const _StartingView(),
          PosSyncPhase.running => _ProgressView(flow: flow),
          PosSyncPhase.done => PosSyncResultView(
            job: flow.job,
            integration: flow.integration,
          ),
          PosSyncPhase.error => PosMessageView(
            icon: Icons.cloud_off_outlined,
            title: flow.message ?? 'Could not read the sync progress.',
            body: 'The job is still on the server — check the sync history '
                'before starting another one.',
            onRetry: () {
              _restartTimer();
              ref.read(posSyncFlowProvider.notifier).poll();
            },
            retryLabel: 'Check again',
            action: TextButton(
              key: const Key('pos-progress-history'),
              onPressed: () => context.push(Routes.posSyncHistory),
              child: const Text('View sync history'),
            ),
          ),
        },
      ),
    );
  }
}

/// Hand-off state while `POST .../sync` is in flight.
class _StartingView extends StatelessWidget {
  const _StartingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            'Starting sync…',
            key: const Key('pos-sync-starting'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

/// Live view of the in-flight job: status chip, indeterminate progress and the
/// server's own counters.
class _ProgressView extends ConsumerWidget {
  const _ProgressView({required this.flow});

  final PosSyncFlowState flow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final job = flow.job!;
    final capped = flow.polls >= kPosSyncMaxPolls;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      PosStatusChip(
                        key: const Key('pos-progress-status'),
                        label: posJobStatusLabel(job.status),
                        color: posJobStatusColor(job.status, scheme),
                        icon: posJobStatusIcon(job.status),
                      ),
                      const Spacer(),
                      PosStatusChip(
                        label: posSyncTypeLabel(job.syncType),
                        color: scheme.outline,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Syncing your products…',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Nothing is counted here — the numbers below come from the '
                    'POS connector.',
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  ),
                  const SizedBox(height: 16),
                  const ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                    child: LinearProgressIndicator(minHeight: 6),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _Counter(
                        key: const Key('pos-progress-processed'),
                        label: 'Processed',
                        value: job.itemsProcessed,
                        color: scheme.onSurface,
                      ),
                      _Counter(
                        key: const Key('pos-progress-succeeded'),
                        label: 'Synced',
                        value: job.itemsSucceeded,
                        color: AppTheme.verifiedGreen,
                      ),
                      _Counter(
                        key: const Key('pos-progress-failed'),
                        label: 'Failed',
                        value: job.itemsFailed,
                        color: scheme.error,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            capped
                ? 'The connector has not reported an outcome yet — use '
                      '"Refresh now" rather than waiting.'
                : 'Checking the server every '
                      '${ref.read(posSyncPollIntervalProvider).inSeconds}s.',
            style: TextStyle(fontSize: 11, color: scheme.outline),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('pos-sync-refresh'),
                  onPressed: () =>
                      ref.read(posSyncFlowProvider.notifier).poll(),
                  child: const Text('Refresh now'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const Key('pos-progress-history'),
                  onPressed: () => context.push(Routes.posSyncHistory),
                  child: const Text('View history'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One live counter of the in-flight job.
class _Counter extends StatelessWidget {
  const _Counter({
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
          '$value',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
