import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_shopkeeper_app/features/insights/domain/insights_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/location_capture_state.dart';

/// Analytics / Reports contract — REAL DATA ONLY.
///
/// Pure-model pins (no widgets, no network): the "only show real data, never
/// fabricate" rule is enforced where it can't be undone — the data layer.
///
/// Rule: an absent / unknown backend section parses to an empty or
/// zero-valued model, and `hasActivity` is false only when there is genuinely
/// nothing to show — so the UI renders an honest empty state instead of an
/// invented number. There are NO revenue / sales-transaction fields in the
/// analytics models (the Sales report is customer-engagement only).
void main() {
  group('InsightsBundle real-data rules', () {
    test('an empty payload is fully zero/empty and is treated as no activity',
        () {
      final bundle = InsightsBundle.fromJson(const <String, dynamic>{});

      // The KPI overview zeroes out.
      expect(bundle.overview.views.today, 0);
      expect(bundle.overview.clicks.today, 0);
      expect(bundle.overview.interactions.today, 0);
      expect(bundle.overview.hasActivity, isFalse);

      // No series, no top products, no searches, no devices, no hourly.
      expect(bundle.viewSeries, isEmpty);
      expect(bundle.clickSeries, isEmpty);
      expect(bundle.topProducts, isEmpty);
      expect(bundle.topSearches, isEmpty);
      expect(bundle.hourly, isEmpty);

      // The device breakdown defaults to total 0.
      expect(bundle.devices.total, 0);
      // Inventory freshness defaults to a zero catalog.
      expect(bundle.freshness.totalProducts, 0);
      expect(bundle.freshness.fresh, 0);
      expect(bundle.freshness.stale, 0);

      // The whole bundle is reported as having no activity.
      expect(bundle.hasActivity, isFalse);
    });

    test('real activity flips every guard correctly', () {
      final bundle = InsightsBundle.fromJson(<String, dynamic>{
        'overview': {
          // Parsed onto TrendMetric: `today`/`this_week`.
          'views': {'today': 3, 'this_week': 21},
          'clicks': {'today': 1, 'this_week': 9},
        },
        'top_searches': [
          {'query': 'bread', 'count': 4},
        ],
      });

      expect(bundle.overview.views.today, 3);
      expect(bundle.overview.clicks.today, 1);
      expect(bundle.overview.hasActivity, isTrue);
      expect(bundle.topSearches, isNotEmpty);
      // Search appearances contribute to activity at the bundle level.
      expect(bundle.hasActivity, isTrue);
      expect(bundle.peakHour, isNull); // no hourly data
    });

    test('peakHour ignores zero-value hours', () {
      final bundle = InsightsBundle.fromJson(<String, dynamic>{
        'hourly': [
          {'hour': 8, 'views': 0},
          {'hour': 12, 'views': 7},
          {'hour': 18, 'views': 0},
        ],
      });
      // 8 and 18 have zero activity — only 12 is a real peak.
      expect(bundle.peakHour?.hour, 12);
      expect(bundle.peakHour?.views, 7);
    });

    test('the Sales route is engagement-only — a revenue field is ignored', () {
      // The backend admin payload may carry a `revenue` key, but the
      // shopkeeper analytics models do NOT surface revenue: a payload whose
      // only "value" is revenue produces NO activity and NO fabricated chart.
      final bundle = InsightsBundle.fromJson(<String, dynamic>{
        'revenue': 250000,
        'total_orders': 500,
      });
      expect(bundle.hasActivity, isFalse);
      expect(bundle.overview.hasActivity, isFalse);
    });

    test('a real GPS fix keeps its REAL accuracy radius, never 0', () {
      // The shopkeeper-facing location model never fabricates 0 m: a GPS fix
      // reports the device's radius, and a hand-placed pin omits the field.
      final gpsFix = CapturedShopLocation(
        latitude: 25.5941,
        longitude: 85.1376,
        accuracyMeters: 7,
        capturedAt: DateTime.utc(2026, 1, 1),
      );
      final meta = gpsFix.toLocationMeta();
      expect(meta['location_source'], 'GPS');
      expect(meta['accuracy_meters'], 7);

      final handPlaced = CapturedShopLocation(
        latitude: 25.6,
        longitude: 85.1,
        capturedAt: DateTime.utc(2026, 1, 1),
        locationSource: 'MANUAL',
      );
      final manualMeta = handPlaced.toLocationMeta();
      expect(manualMeta['location_source'], 'MANUAL');
      expect(manualMeta.containsKey('accuracy_meters'), isFalse,
          reason: 'no fix → no accuracy, never 0 m');
    });
  });

  group('FocusedReport sales disclaimer', () {
    test('sales titles as "Sales report" and carries no revenue field', () {
      expect(FocusedReport.sales.title, 'Sales report');
      // The analytics layer has no revenue concept to assert presence of —
      // the negative assertion above (revenue field is ignored) is the test.
    });
  });
}
