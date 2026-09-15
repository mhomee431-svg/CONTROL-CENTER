import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../domain/insights_models.dart';
import '../controllers/insights_controller.dart';

/// Reports / Insights — the shopkeeper's customer-activity read for the
/// selected shop.
///
/// Every number comes from the backend's analytics event stream (shop views,
/// product clicks, customer interactions and inventory freshness) over a
/// selectable trailing window. Nothing is computed or invented client-side:
/// a shop without activity gets an honest empty state.
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(insightsControllerProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Switching businesses re-scopes the report to the newly selected shop.
    ref.listen(selectedShopProvider, (prev, next) {
      if (prev?.id != next?.id) {
        ref.read(insightsControllerProvider.notifier).load();
      }
    });

    final state = ref.watch(insightsControllerProvider);
    final shopName = ref.watch(selectedShopProvider)?.name;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & insights'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () =>
                ref.read(insightsControllerProvider.notifier).load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(state, shopName)),
    );
  }

  Widget _buildBody(InsightsState state, String? shopName) {
    switch (state.status) {
      case InsightsStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case InsightsStatus.noShop:
        return const _MessageView(
          icon: Icons.storefront_outlined,
          title: 'No shop selected',
          message: 'Set up your shop to unlock its reports and insights.',
        );
      case InsightsStatus.accessDenied:
        return _MessageView(
          icon: Icons.lock_outline,
          title: 'Reports unavailable',
          message: state.message ?? 'You do not have access to this shop.',
          actionLabel: 'Retry',
          onAction: () => ref.read(insightsControllerProvider.notifier).load(),
        );
      case InsightsStatus.error:
        return _MessageView(
          icon: Icons.error_outline,
          title: 'Could not load reports',
          message: state.message ?? 'Something went wrong.',
          actionLabel: 'Retry',
          onAction: () => ref.read(insightsControllerProvider.notifier).load(),
        );
      case InsightsStatus.ready:
        return RefreshIndicator(
          onRefresh: () =>
              ref.read(insightsControllerProvider.notifier).load(),
          child: _ReportBody(
            bundle: state.bundle!,
            rangeDays: state.rangeDays,
            shopName: shopName,
          ),
        );
    }
  }
}

/// Placeholder state: no shop yet, or the report could not be loaded.
class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: scheme.outline),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.outline),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// The loaded report: window selector, KPI cards, then one card per insight.
class _ReportBody extends StatelessWidget {
  const _ReportBody({
    required this.bundle,
    required this.rangeDays,
    this.shopName,
  });

  final InsightsBundle bundle;
  final int rangeDays;
  final String? shopName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          shopName == null
              ? 'Customer activity'
              : 'Customer activity · $shopName',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'Trailing $rangeDays days, computed from live customer activity.',
          style: TextStyle(fontSize: 12, color: scheme.outline),
        ),
        const SizedBox(height: 12),
        _RangeSelector(selected: rangeDays),
        const SizedBox(height: 16),
        if (!bundle.hasActivity) _NoActivityCard(rangeDays: rangeDays),
        if (bundle.hasActivity) ...[
          _KpiRow(overview: bundle.overview),
          const SizedBox(height: 12),
          _WeeklyCard(overview: bundle.overview),
          const SizedBox(height: 12),
        ],
        _TopProductsCard(products: bundle.topProducts),
        const SizedBox(height: 12),
        _SearchesCard(terms: bundle.topSearches),
        const SizedBox(height: 12),
        _InteractionsCard(interactions: bundle.interactions),
        const SizedBox(height: 12),
        _DevicesCard(devices: bundle.devices),
        const SizedBox(height: 12),
        _HourlyCard(points: bundle.hourly, peak: bundle.peakHour),
        const SizedBox(height: 12),
        _FreshnessCard(freshness: bundle.freshness),
        const SizedBox(height: 24),
        Text(
          'All metrics are computed by the backend from live customer activity.',
          style: TextStyle(fontSize: 11, color: scheme.outline),
        ),
      ],
    );
  }
}

/// Trailing-window selector (7 / 30 / 90 days).
class _RangeSelector extends ConsumerWidget {
  const _RangeSelector({required this.selected});

  final int selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 8,
      children: [
        for (final days in kInsightsRanges)
          ChoiceChip(
            key: Key('insights-range-$days'),
            label: Text('$days days'),
            selected: days == selected,
            onSelected: (_) =>
                ref.read(insightsControllerProvider.notifier).setRange(days),
          ),
      ],
    );
  }
}

/// Headline KPI cards — stacked on narrow screens, side by side when wide.
class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.overview});

  final InsightsOverview overview;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _KpiCard(label: 'Views today', trend: overview.views),
      _KpiCard(label: 'Clicks today', trend: overview.clicks),
      _KpiCard(label: 'Interactions today', trend: overview.interactions),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                cards[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
    );
  }
}

/// One KPI card: today's value with the backend-computed delta vs yesterday.
class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.label, required this.trend});

  final String label;
  final TrendMetric trend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = trend.isGrowing
        ? AppTheme.verifiedGreen
        : trend.isDeclining
        ? scheme.error
        : scheme.outline;
    final icon = trend.isGrowing
        ? Icons.trending_up
        : trend.isDeclining
        ? Icons.trending_down
        : Icons.trending_flat;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: scheme.outline)),
            const SizedBox(height: 6),
            Text(
              '${trend.today}',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Text(
                  trend.changeLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'vs yesterday',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: scheme.outline),
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

/// Card wrapper with a section title.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// Shared "nothing recorded yet" line used by the insight cards.
class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}

/// Honest empty state for a shop with no recorded customer activity yet.
class _NoActivityCard extends StatelessWidget {
  const _NoActivityCard({required this.rangeDays});

  final int rangeDays;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.visibility_outlined, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              'No customer activity yet',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Nothing has been recorded in the last $rangeDays days. These '
              'reports fill in automatically once customers view your shop '
              'and products.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

/// Weekly totals with the week-over-week delta.
class _WeeklyCard extends StatelessWidget {
  const _WeeklyCard({required this.overview});

  final InsightsOverview overview;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'This week',
      child: Column(
        children: [
          _MetricRow(
            label: 'Shop views',
            value: overview.views.thisWeek,
            delta: overview.views.weekChangeLabel,
          ),
          _MetricRow(
            label: 'Product clicks',
            value: overview.clicks.thisWeek,
            delta: overview.clicks.weekChangeLabel,
          ),
          _MetricRow(
            label: 'Interactions',
            value: overview.interactions.thisWeek,
            delta: overview.interactions.weekChangeLabel,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

/// One label / value / delta row inside a card.
class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    this.delta,
    this.isLast = false,
  });

  final String label;
  final int value;
  final String? delta;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(
            '$value',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          if (delta != null) ...[
            const SizedBox(width: 8),
            Text(
              delta!,
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ],
        ],
      ),
    );
  }
}

/// Most-viewed products in the window.
class _TopProductsCard extends StatelessWidget {
  const _TopProductsCard({required this.products});

  final List<TopProduct> products;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _SectionCard(
      title: 'Top products',
      child: products.isEmpty
          ? const _EmptyLine('No product views in this window yet.')
          : Column(
              children: [
                for (var i = 0; i < products.length; i++)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 26,
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            products[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          '${products[i].views} views',
                          style: TextStyle(fontSize: 12, color: scheme.outline),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// What customers searched before landing on this shop.
class _SearchesCard extends StatelessWidget {
  const _SearchesCard({required this.terms});

  final List<SearchTerm> terms;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Customer searches',
      child: terms.isEmpty
          ? const _EmptyLine('No customer searches recorded yet.')
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final term in terms)
                  Chip(
                    label: Text('${term.query} · ${term.count}'),
                    labelStyle: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
    );
  }
}

/// Customer interactions by type.
class _InteractionsCard extends StatelessWidget {
  const _InteractionsCard({required this.interactions});

  final InteractionBreakdown interactions;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Customer interactions',
      child: interactions.isEmpty
          ? const _EmptyLine('No calls, messages or ratings yet.')
          : Column(
              children: [
                _MetricRow(label: 'Call views', value: interactions.callViews),
                _MetricRow(label: 'Messages', value: interactions.messages),
                _MetricRow(
                  label: 'Ratings',
                  value: interactions.ratings,
                  isLast: true,
                ),
              ],
            ),
    );
  }
}

/// Which devices customers use to discover the shop.
class _DevicesCard extends StatelessWidget {
  const _DevicesCard({required this.devices});

  final DeviceBreakdown devices;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shares = devices.shares;
    return _SectionCard(
      title: 'Devices',
      child: devices.isEmpty
          ? const _EmptyLine('No device data recorded yet.')
          : Column(
              children: [
                for (var i = 0; i < shares.length; i++)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                shares[i].label,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            Text(
                              '${shares[i].count} · ${shares[i].shareLabel}',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.outline,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: shares[i].share,
                            minHeight: 6,
                            backgroundColor: scheme.surfaceContainerHighest,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Hour-of-day shop-view distribution (peak hours).
class _HourlyCard extends StatelessWidget {
  const _HourlyCard({required this.points, this.peak});

  final List<HourlyPoint> points;
  final HourlyPoint? peak;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final busiest = peak;
    if (points.isEmpty) {
      return _SectionCard(
        title: 'Peak hours',
        child: const _EmptyLine('No shop views recorded yet.'),
      );
    }
    final maxViews = points.fold(
      0,
      (max, point) => point.views > max ? point.views : max,
    );
    return _SectionCard(
      title: 'Peak hours',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (busiest != null)
            Text(
              'Busiest hour: ${busiest.label} · ${busiest.views} views',
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
          const SizedBox(height: 12),
          SizedBox(
            height: 128,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final point in points)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            // Bars scale to the busiest hour in the window; a
                            // zero hour keeps a 4px stub so the axis stays
                            // readable.
                            height: maxViews == 0
                                ? 4
                                : 4 + (88 * (point.views / maxViews)),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            point.hour % 6 == 0
                                ? point.label.substring(0, 2)
                                : '',
                            style: TextStyle(
                              fontSize: 9,
                              color: scheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Inventory freshness — how recently stock was updated.
class _FreshnessCard extends StatelessWidget {
  const _FreshnessCard({required this.freshness});

  final InventoryFreshness freshness;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!freshness.hasProducts) {
      return _SectionCard(
        title: 'Inventory freshness',
        child: const _EmptyLine('No products in your catalog yet.'),
      );
    }
    return _SectionCard(
      title: 'Inventory freshness',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${freshness.scoreLabel} of '
                  '${freshness.totalProducts} products',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                'updated in the last 24h',
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: freshness.scoreFraction,
              minHeight: 8,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${freshness.fresh} fresh · ${freshness.stale} stale',
            style: TextStyle(fontSize: 12, color: scheme.outline),
          ),
        ],
      ),
    );
  }
}