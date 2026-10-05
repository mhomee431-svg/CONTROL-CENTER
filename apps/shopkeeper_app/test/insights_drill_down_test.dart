import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/insights/data/insights_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/insights/domain/insights_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/insights/presentation/controllers/insights_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/insights/presentation/screens/insights_drill_down_screen.dart';

import 'fakes.dart';

InsightsPoint _point(String date, int value) =>
    InsightsPoint(date: date, value: value);

/// `2026-01-01` — the ISO day labels the daily series uses.
String _iso(DateTime day) => '${day.year}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Counts element accesses to a list, so a regression back to scanning the
/// series inside the row loop fails the suite instead of silently making the
/// screen quadratic again.
///
/// Counting reads of the *derivation* would not catch that: the quadratic shape
/// inlines its own scan and never touches the derivation at all.
class _CountingList<T> extends ListBase<T> {
  _CountingList(this._inner);

  final List<T> _inner;
  int reads = 0;

  @override
  int get length {
    reads++;
    return _inner.length;
  }

  @override
  set length(int value) => _inner.length = value;

  @override
  T operator [](int index) {
    reads++;
    return _inner[index];
  }

  @override
  void operator []=(int index, T value) => _inner[index] = value;
}

/// Serves an injected [DrillDownState] and never re-fetches, so a widget test
/// measures the screen's own derivations rather than the network.
class _CountingController extends InsightsDrillDownsController {
  _CountingController(this._initial);

  final Map<DrillDownMetric, DrillDownState> _initial;

  @override
  Map<DrillDownMetric, DrillDownState> build() => _initial;

  @override
  Future<void> load(DrillDownMetric metric, {int? days}) async {}
}

void main() {
  group('InsightsDrillDownsController', () {
    ProviderContainer makeContainer(FakeInsightsRepo repo, {int? shopId = 10}) {
      final container = ProviderContainer(overrides: [
        insightsRepositoryProvider.overrideWithValue(repo),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider.overrideWith(() =>
            SelectedShopOverride(shopId == null ? null : ownerShop(id: shopId))),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('views drill-down fetches the daily series AND the hourly spread',
        () async {
      final repo = FakeInsightsRepo(
        viewsSeries: [_point('2026-01-12', 8), _point('2026-01-13', 3)],
        hourly: [const HourlyPoint(hour: 18, views: 12)],
      );
      final container = makeContainer(repo);

      await container
          .read(insightsDrillDownsProvider.notifier)
          .load(DrillDownMetric.views);

      final state =
          container.read(insightsDrillDownsProvider)[DrillDownMetric.views]!;
      expect(state.status, DrillDownStatus.ready);
      expect(state.series, hasLength(2));
      expect(state.total, 11);
      expect(state.peakHour!.label, '18:00');
      expect(repo.viewsCalls, 1);
      expect(repo.hourlyCalls, 1);
    });

    test('clicks drill-down requests the EXTENDED top-products list',
        () async {
      final repo = FakeInsightsRepo(
        clicksSeries: [_point('2026-01-12', 5)],
        topProducts: const [
          TopProduct(shopProductId: 1, sku: 'SKU-A', views: 9),
          TopProduct(shopProductId: 2, sku: '', views: 4),
        ],
      );
      final container = makeContainer(repo);

      await container
          .read(insightsDrillDownsProvider.notifier)
          .load(DrillDownMetric.clicks);

      final state =
          container.read(insightsDrillDownsProvider)[DrillDownMetric.clicks]!;
      expect(state.status, DrillDownStatus.ready);
      expect(state.topProducts, hasLength(2));
      // The drill-down asks for up to 50 rows — the combined report ships 10.
      expect(repo.lastTopProductsLimit, kInsightsMaxTopProducts);
      expect(repo.lastTopProductsLimit, greaterThan(10));
      // SKU-less products fall back to an honest id label.
      expect(state.topProducts[1].label, 'Product #2');
      // No peak-hour data is fetched for the clicks metric.
      expect(repo.hourlyCalls, 0);
    });

    test('hourly window is capped at 90 days for wide ranges', () async {
      final repo = FakeInsightsRepo();
      final container = makeContainer(repo);

      await container
          .read(insightsDrillDownsProvider.notifier)
          .load(DrillDownMetric.views, days: 365);

      expect(repo.lastDays, 365);
      expect(repo.lastHourlyDays, 90);
    });

    test('range switch refetches with the new window', () async {
      final repo = FakeInsightsRepo(viewsSeries: [_point('2026-01-12', 2)]);
      final container = makeContainer(repo);
      final controller = container.read(insightsDrillDownsProvider.notifier);

      await controller.setRange(DrillDownMetric.views, 7);

      final state =
          container.read(insightsDrillDownsProvider)[DrillDownMetric.views]!;
      expect(state.rangeDays, 7);
      expect(repo.lastDays, 7);
      expect(repo.viewsCalls, 1);
    });

    test('403 becomes the access-denied copy', () async {
      final repo = FakeInsightsRepo(
        error: const ApiException(statusCode: 403, message: 'denied'),
      );
      final container = makeContainer(repo);

      await container
          .read(insightsDrillDownsProvider.notifier)
          .load(DrillDownMetric.views);

      final state =
          container.read(insightsDrillDownsProvider)[DrillDownMetric.views]!;
      expect(state.status, DrillDownStatus.error);
      expect(state.message, contains('do not have access'));
    });

    test('no shop selected fails fast without calling the API', () async {
      final repo = FakeInsightsRepo();
      final container = makeContainer(repo, shopId: null);

      await container
          .read(insightsDrillDownsProvider.notifier)
          .load(DrillDownMetric.clicks);

      final state =
          container.read(insightsDrillDownsProvider)[DrillDownMetric.clicks]!;
      expect(state.status, DrillDownStatus.error);
      expect(state.message, contains('No shop selected'));
      expect(repo.clicksCalls, 0);
    });

    test('one metric loading never clobbers the other metric’s state',
        () async {
      final repo = FakeInsightsRepo(
        viewsSeries: [_point('2026-01-12', 8)],
        clicksSeries: [_point('2026-01-12', 5)],
      );
      final container = makeContainer(repo);
      final controller = container.read(insightsDrillDownsProvider.notifier);

      await controller.load(DrillDownMetric.views);
      expect(
        container
            .read(insightsDrillDownsProvider)[DrillDownMetric.clicks]!.status,
        DrillDownStatus.loading,
      );

      await controller.load(DrillDownMetric.clicks);
      final views =
          container.read(insightsDrillDownsProvider)[DrillDownMetric.views]!;
      final clicks =
          container.read(insightsDrillDownsProvider)[DrillDownMetric.clicks]!;
      expect(views.status, DrillDownStatus.ready);
      expect(views.total, 8);
      expect(clicks.total, 5);
    });
  });

  group('DrillDownState derivations (chart scale + peak hours)', () {
    DrillDownState ready({
      List<InsightsPoint> series = const [],
      List<HourlyPoint> hourly = const [],
    }) =>
        DrillDownState(
          status: DrillDownStatus.ready,
          metric: DrillDownMetric.views,
          series: series,
          hourly: hourly,
        );

    test('peakSeriesValue is the largest daily point, 0 when empty', () {
      expect(ready().peakSeriesValue, 0);
      expect(
        ready(series: [
          _point('2026-01-12', 3),
          _point('2026-01-13', 44),
          _point('2026-01-14', 9),
        ]).peakSeriesValue,
        44,
      );
    });

    test('peakSeriesValue stays 0 for an all-zero series', () {
      // Never negative: the bar maths relies on this as the chart scale.
      expect(ready(series: [_point('2026-01-12', 0)]).peakSeriesValue, 0);
    });

    test('busiestHours ranks descending and drops zero-traffic hours', () {
      final top = ready(hourly: const [
        HourlyPoint(hour: 0, views: 0),
        HourlyPoint(hour: 9, views: 4),
        HourlyPoint(hour: 18, views: 12),
        HourlyPoint(hour: 21, views: 7),
        HourlyPoint(hour: 23, views: 0),
      ]).busiestHours();

      expect(top.map((p) => p.hour), [18, 21, 9]);
      // The card reads its scale off the top entry (sorted once).
      expect(top.first.views, 12);
    });

    test('busiestHours returns fewer rows when traffic is thin', () {
      expect(ready().busiestHours(), isEmpty);
      expect(
        ready(hourly: const [HourlyPoint(hour: 5, views: 2)]).busiestHours(),
        hasLength(1),
      );
    });

    test('busiestHours honours an explicit limit', () {
      final state = ready(hourly: const [
        HourlyPoint(hour: 8, views: 1),
        HourlyPoint(hour: 9, views: 2),
        HourlyPoint(hour: 10, views: 3),
        HourlyPoint(hour: 11, views: 4),
      ]);

      expect(state.busiestHours(limit: 2).map((p) => p.hour), [11, 10]);
      expect(state.busiestHours(limit: 99), hasLength(4));
    });
  });

  group('InsightsDrillDownScreen (widget)', () {
    Widget wrap(FakeInsightsRepo repo, DrillDownMetric metric) =>
        ProviderScope(
          overrides: [
            insightsRepositoryProvider.overrideWithValue(repo),
            tokenStoreProvider.overrideWithValue(
                InMemoryTokenStore(accessToken: 'test-access-token')),
            selectedShopProvider
                .overrideWith(() => SelectedShopOverride(ownerShop(id: 10))),
          ],
          child: MaterialApp(home: InsightsDrillDownScreen(metric: metric)),
        );

    testWidgets('views detail shows the headline, daily rows and peak hours',
        (tester) async {
      final repo = FakeInsightsRepo(
        viewsSeries: [
          _point('2026-01-12', 8),
          _point('2026-01-13', 3),
        ],
        hourly: const [
          HourlyPoint(hour: 18, views: 12),
          HourlyPoint(hour: 9, views: 4),
          HourlyPoint(hour: 0, views: 0),
        ],
      );
      await tester.pumpWidget(wrap(repo, DrillDownMetric.views));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('drilldown-headline')), findsOneWidget);
      expect(find.text('11 views'), findsOneWidget);
      expect(find.text('12 Jan'), findsOneWidget);
      expect(find.text('13 Jan'), findsOneWidget);
      // Only hours with real traffic appear (midnight with 0 is dropped) —
      // top-3 busiest first.
      expect(find.text('18:00'), findsOneWidget);
      expect(find.text('09:00'), findsOneWidget);
      expect(find.text('00:00'), findsNothing);
    });

    testWidgets('a wide window renders the whole series against one scale',
        (tester) async {
      // Regression guard for the hoisted derivations: the chart maximum and the
      // peak-hours ranking are read ONCE per build. When the maximum was folded
      // inside each row's arguments this screen visited the 90-point series 90
      // times per frame, and re-sorted the hourly spread once per rendered row.
      final repo = FakeInsightsRepo(
        viewsSeries: [
          for (var i = 0; i < 90; i++)
            _point(_iso(DateTime(2026, 1, 1).add(Duration(days: i))), i + 1),
        ],
        hourly: const [HourlyPoint(hour: 18, views: 12)],
      );
      await tester.pumpWidget(wrap(repo, DrillDownMetric.views));
      await tester.pumpAndSettle();

      // All ninety points reached the headline (1 + 2 + … + 90).
      expect(find.text('${90 * 91 ~/ 2} views'), findsOneWidget);
      // The oldest day is in view, labelled from its ISO date.
      expect(find.text('01 Jan'), findsOneWidget);
      // The peak-hours card is below the fold but still rendered.
      await tester.scrollUntilVisible(find.text('18:00'), 400);
      expect(find.text('18:00'), findsOneWidget);
    });

    testWidgets('the daily series is scanned linearly, not once per row',
        (tester) async {
      Future<int> seriesReadsFor(int window) async {
        // Tear the previous tree down first: pumping a second ProviderScope in
        // the same test otherwise reuses the live container, and the second
        // measurement would read the first window's state.
        await tester.pumpWidget(const SizedBox.shrink());
        final series = _CountingList<InsightsPoint>([
          for (var i = 0; i < window; i++)
            _point(_iso(DateTime(2026, 1, 1).add(Duration(days: i))), i + 1),
        ]);
        await tester.pumpWidget(ProviderScope(
          overrides: [
            insightsDrillDownsProvider.overrideWith(
              () => _CountingController({
                DrillDownMetric.views: DrillDownState(
                  status: DrillDownStatus.ready,
                  metric: DrillDownMetric.views,
                  series: series,
                  hourly: const [HourlyPoint(hour: 18, views: 12)],
                ),
              }),
            ),
          ],
          child: const MaterialApp(
            home: InsightsDrillDownScreen(metric: DrillDownMetric.views),
          ),
        ));
        await tester.pumpAndSettle();
        return series.reads;
      }

      final narrow = await seriesReadsFor(15);
      final wide = await seriesReadsFor(90);

      // Six times the window costs about six times the scans — the chart scale
      // is one pass over the series and the rows are another. Folding the
      // maximum inside each row's arguments, the shape this guard exists for,
      // costs ~30x the window instead (~16.8k accesses at 90 days vs ~550), so
      // a linear screen sits well inside this bound and a quadratic one does
      // not.
      expect(narrow, greaterThan(0));
      expect(wide, lessThanOrEqualTo(narrow * 12));
    });

    testWidgets('clicks detail shows ranked top products', (tester) async {
      final repo = FakeInsightsRepo(
        clicksSeries: [_point('2026-01-12', 5)],
        topProducts: const [
          TopProduct(shopProductId: 1, sku: 'AATA-5KG', views: 9),
          TopProduct(shopProductId: 2, sku: 'CHAI-250G', views: 4),
        ],
      );
      await tester.pumpWidget(wrap(repo, DrillDownMetric.clicks));
      await tester.pumpAndSettle();

      expect(find.text('AATA-5KG'), findsOneWidget);
      expect(find.text('CHAI-250G'), findsOneWidget);
      expect(find.textContaining('up to 50'), findsOneWidget);
    });

    testWidgets('shows the error with a working Retry', (tester) async {
      final repo = FakeInsightsRepo(
        error: const ApiException(statusCode: 500, message: 'Server down'),
      );
      await tester.pumpWidget(wrap(repo, DrillDownMetric.views));
      await tester.pumpAndSettle();

      expect(find.text('Server down'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      repo.error = null;
      repo.viewsSeries = [_point('2026-01-12', 8)];
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Server down'), findsNothing);
      expect(find.text('8 views'), findsOneWidget);
    });
  });
}
