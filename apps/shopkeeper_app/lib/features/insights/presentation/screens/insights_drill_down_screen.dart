import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/state/system_state.dart';
import '../../../../core/state/system_state_view.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/insights_models.dart';
import '../controllers/insights_controller.dart';

/// KPI drill-down detail: one metric, its own window, granular endpoints.
///
/// Views â†’ daily series + hour-of-day distribution (up to a 90-day window,
/// wider than the combined report's 30-day hourly cap).
/// Clicks â†’ daily series + ranked top products (up to 50 rows, not 10).
class InsightsDrillDownScreen extends ConsumerStatefulWidget {
  const InsightsDrillDownScreen({super.key, required this.metric});

  final DrillDownMetric metric;

  /// Builds the screen from a `go_router` path parameter.
  static Widget fromRoute(dynamic segment) => InsightsDrillDownScreen(
        metric: DrillDownMetricX.fromRoute(segment as String?),
      );

  @override
  ConsumerState<InsightsDrillDownScreen> createState() =>
      _InsightsDrillDownScreenState();
}

class _InsightsDrillDownScreenState
    extends ConsumerState<InsightsDrillDownScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() =>
        ref.read(insightsDrillDownsProvider.notifier).load(widget.metric));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(insightsDrillDownsProvider)[widget.metric]!;

    return Scaffold(
      appBar: AppBar(title: Text(widget.metric.title)),
      body: SafeArea(
        child: switch (state.status) {
          DrillDownStatus.loading => const Center(
              child: CircularProgressIndicator(),
            ),
          DrillDownStatus.error => _ErrorView(
              message: state.message ?? 'Something went wrong.',
              onRetry: () => ref
                  .read(insightsDrillDownsProvider.notifier)
                  .load(widget.metric),
            ),
          DrillDownStatus.ready => _ReadyView(state: state),
        },
      ),
    );
  }
}


/// Everything the ready state renders.
class _ReadyView extends StatelessWidget {
  const _ReadyView({required this.state});

  final DrillDownState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _RangeSelector(
          selected: state.rangeDays,
          onChanged: (days) => _dispatchRange(context, state.metric, days),
        ),
        const SizedBox(height: 16),
        _HeadlineCard(state: state),
        const SizedBox(height: 16),
        if (state.series.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No customer activity in this window yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.outline),
            ),
          )
        else
          _SectionCard(
            title: 'Daily ${state.metric.unitLabel}',
            child: Column(
              children: [
                for (final point in state.series)
                  _SeriesRow(
                    label: _dayLabel(point.date),
                    value: point.value,
                    max: state.series
                        .fold(0, (m, p) => p.value > m ? p.value : m),
                    unit: state.metric.unitLabel,
                  ),
              ],
            ),
          ),
        if (state.metric == DrillDownMetric.views &&
            state.hourly.any((p) => p.views > 0)) ...[
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Peak hours',
            child: Column(
              children: [
                for (final point in _topHours(state))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Text(point.label,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    title: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _fraction(
                            point.views, _topHours(state).first.views),
                        minHeight: 6,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                    trailing: Text('${point.views}'),
                  ),
              ],
            ),
          ),
        ],
        if (state.metric == DrillDownMetric.clicks &&
            state.topProducts.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Top products (up to $kInsightsMaxTopProducts)',
            child: Column(
              children: [
                for (var i = 0; i < state.topProducts.length; i++)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: _RankBadge(rank: i + 1),
                    title: Text(
                      state.topProducts[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      '${state.topProducts[i].views} ${state.metric.unitLabel}',
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _dispatchRange(BuildContext context, DrillDownMetric metric, int days) {
    // The stateless view has no ref of its own â€” read through the scope.
    final container = ProviderScope.containerOf(context);
    container
        .read(insightsDrillDownsProvider.notifier)
        .setRange(metric, days);
  }

  /// Top-3 busiest hours, descending.
  List<HourlyPoint> _topHours(DrillDownState state) {
    final sorted = [...state.hourly]..sort((a, b) => b.views - a.views);
    return sorted.take(3).where((p) => p.views > 0).toList(growable: false);
  }

  static double _fraction(int value, int max) =>
      max <= 0 ? 0 : (value / max).clamp(0.0, 1.0);

  /// `2026-01-12` â†’ `12 Jan` (compact rows; the window is at most 90 days).
  static String _dayLabel(String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) return iso;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final day = int.tryParse(parts[2]) ?? 0;
    final month = int.tryParse(parts[1]) ?? 1;
    if (day < 1 || day > 31 || month < 1 || month > 12) return iso;
    return '${parts[2]} ${months[month - 1]}';
  }
}

/// Failure view — the shared system-state renderer with the drill-down's own
/// retry key. The state (offline / server / maintenance / generic) comes from
/// the controller's message, so the icon and way out match the real cause.
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final carried = SystemStateSpec.fromMessage(message);
    return SystemStateView(
      spec: carried != null
          ? SystemStateSpec.of(carried)
          : SystemStateSpec(
              state: SystemState.genericRetry,
              title: 'Could not load this report',
              message: message,
              icon: Icons.error_outline,
              action: SystemAction.retry,
            ),
      onRetry: onRetry,
      retryKey: const Key('drilldown-retry'),
    );
  }
}

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      key: const Key('drilldown-range'),
      segments: [
        for (final days in kInsightsRanges)
          ButtonSegment(value: days, label: Text('$days days')),
      ],
      selected: {selected},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class _HeadlineCard extends StatelessWidget {
  const _HeadlineCard({required this.state});

  final DrillDownState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('drilldown-headline'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              state.metric == DrillDownMetric.views
                  ? Icons.visibility_outlined
                  : Icons.touch_app_outlined,
              color: AppTheme.brandSeed,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total in last ${state.rangeDays} days',
                      style: TextStyle(fontSize: 12, color: scheme.outline)),
                  Text(
                    '${state.total} ${state.metric.unitLabel}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
            ),
            if (state.peakHour != null)
              Chip(
                avatar: const Icon(Icons.schedule, size: 16),
                label: Text('Peak ${state.peakHour!.label}'),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _SeriesRow extends StatelessWidget {
  const _SeriesRow({
    required this.label,
    required this.value,
    required this.max,
    required this.unit,
  });

  final String label;
  final int value;
  final int max;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: max <= 0 ? 0 : (value / max).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text('$value',
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 12, color: scheme.outline)),
          ),
        ],
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: 12,
      backgroundColor: rank <= 3 ? AppTheme.brandSeed : scheme.surfaceContainerHighest,
      child: Text(
        '$rank',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: rank <= 3 ? Colors.white : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Navigates from the Reports screen KPI row to this detail screen.
void openDrillDown(BuildContext context, DrillDownMetric metric) {
  context.push(Routes.insightsDrillDown(metric.routeSegment));
}
