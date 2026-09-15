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
