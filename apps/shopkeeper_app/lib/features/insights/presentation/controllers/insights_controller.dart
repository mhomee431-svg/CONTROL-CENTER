import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/token_store.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../data/insights_repository.dart';
import '../../domain/insights_models.dart';

/// Load states for the Reports / Insights screen.
enum InsightsStatus { loading, ready, noShop, accessDenied, error }

class InsightsState {
  const InsightsState({
    required this.status,
    this.bundle,
    this.rangeDays = kInsightsDefaultRange,
    this.message,
    this.businessInsights,
    this.insightsError,
  });

  final InsightsStatus status;
  final InsightsBundle? bundle;

  /// Trailing window (days) the current [bundle] was computed for.
  final int rangeDays;
  final String? message;

  /// Live business-insight cards for the same shop (top products, low stock,
  /// stale inventory, search visibility, offers performance, profile
  /// completeness). Null when that sub-call failed — [insightsError] then
  /// carries the reason, so the section reports the failure instead of
  /// pretending the shop has nothing to show.
  final BusinessInsightsBundle? businessInsights;
  final String? insightsError;

  factory InsightsState.loading({int rangeDays = kInsightsDefaultRange}) =>
      InsightsState(status: InsightsStatus.loading, rangeDays: rangeDays);

  /// Shown when no shop is selected yet — the screen asks for shop setup
  /// instead of reporting on nothing.
  factory InsightsState.noShop({int rangeDays = kInsightsDefaultRange}) =>
      InsightsState(status: InsightsStatus.noShop, rangeDays: rangeDays);

  bool get isReady => status == InsightsStatus.ready && bundle != null;
}

final insightsControllerProvider =
    NotifierProvider<InsightsController, InsightsState>(InsightsController.new);

class InsightsController extends Notifier<InsightsState> {
  @override
  InsightsState build() => InsightsState.loading();

  InsightsRepository get _repo => ref.read(insightsRepositoryProvider);

  /// Loads the full analytics report for the selected shop. [days] switches
  /// the reporting window (defaults to the current / default range).
  Future<void> load({int? days}) async {
    final rangeDays = days ?? state.rangeDays;
    final shop = ref.read(selectedShopProvider);
    if (shop == null) {
      state = InsightsState.noShop(rangeDays: rangeDays);
      return;
    }
    state = InsightsState.loading(rangeDays: rangeDays);
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      final bundle = await _repo.fetchInsights(shop.id, token, days: rangeDays);
      // The insight cards come from a second, independent call: the analytics
      // report stays truthful (and visible) if that sub-call fails, and the
      // section then says so instead of rendering a fake empty state. A 403 is
      // rethrown — it means the shop itself is off limits, which the outer
      // catch classifies as `accessDenied`.
      BusinessInsightsBundle? businessInsights;
      String? insightsError;
      try {
        businessInsights = await _repo.fetchBusinessInsights(shop.id, token);
      } on ApiException catch (e) {
        if (e.isForbidden) rethrow;
        insightsError = e.message;
      } catch (_) {
        insightsError = 'Business insights could not be loaded.';
      }
      state = InsightsState(
        status: InsightsStatus.ready,
        bundle: bundle,
        businessInsights: businessInsights,
        insightsError: insightsError,
        rangeDays: rangeDays,
      );
    } on ApiException catch (e) {
      // The backend refuses shops the user holds no `dashboard:read` grant on
      // — a distinct state, not a generic failure.
      state = InsightsState(
        status: e.isForbidden
            ? InsightsStatus.accessDenied
            : InsightsStatus.error,
        rangeDays: rangeDays,
        message: e.message,
      );
    } catch (_) {
      state = InsightsState(
        status: InsightsStatus.error,
        rangeDays: rangeDays,
        message: 'Could not load your reports.',
      );
    }
  }

  /// Switches the reporting window and reloads the report.
  Future<void> setRange(int days) => load(days: days);

  /// Clears cached report data (called on logout) so the previous account's
  /// customer metrics never survive into the next session.
  void reset() => state = InsightsState.loading();
}

/// Load states for one KPI drill-down.
enum DrillDownStatus { loading, ready, error }

class DrillDownState {
  const DrillDownState({
    required this.status,
    required this.metric,
    this.rangeDays = kInsightsDefaultRange,
    this.series = const <InsightsPoint>[],
    this.hourly = const <HourlyPoint>[],
    this.topProducts = const <TopProduct>[],
    this.message,
  });

  final DrillDownStatus status;
  final DrillDownMetric metric;

  /// Trailing window (days) the current data was computed for.
  final int rangeDays;

  /// Daily series (views OR clicks — whichever [metric] selects).
  final List<InsightsPoint> series;

  /// Hour-of-day distribution — views drill-down only.
  final List<HourlyPoint> hourly;

  /// Ranked products — clicks drill-down only (up to 50 rows).
  final List<TopProduct> topProducts;

  /// Error copy when [status] is [DrillDownStatus.error].
  final String? message;

  factory DrillDownState.loading(DrillDownMetric metric,
          {int rangeDays = kInsightsDefaultRange}) =>
      DrillDownState(
        status: DrillDownStatus.loading,
        metric: metric,
        rangeDays: rangeDays,
      );

  /// Busiest hour with real traffic, or null when there is nothing yet.
  HourlyPoint? get peakHour {
    HourlyPoint? peak;
    for (final point in hourly) {
      if (point.views <= 0) continue;
      if (peak == null || point.views > peak.views) peak = point;
    }
    return peak;
  }

  /// Total across the daily series (drives the headline number).
  int get total =>
      series.fold(0, (sum, point) => sum + point.value);
}

/// Per-metric drill-down state, held in ONE map owned by ONE controller.
///
/// (The project's Riverpod version has no family notifiers — and a single
/// map keeps the SSOT story simple: every drill-down's state lives here, the
/// screens only render slices.)
final insightsDrillDownsProvider =
    NotifierProvider<InsightsDrillDownsController, Map<DrillDownMetric,
        DrillDownState>>(InsightsDrillDownsController.new);

class InsightsDrillDownsController
    extends Notifier<Map<DrillDownMetric, DrillDownState>> {
  @override
  Map<DrillDownMetric, DrillDownState> build() => {
        for (final metric in DrillDownMetric.values)
          metric: DrillDownState.loading(metric),
      };

  InsightsRepository get _repo => ref.read(insightsRepositoryProvider);

  /// Fetches [metric]'s granular data over [days] for the selected shop.
  ///
  /// Views also pull the hour-of-day distribution; clicks also pull the
  /// extended top-products list (up to 50 rows — more than the combined
  /// report shows).
  Future<void> load(DrillDownMetric metric, {int? days}) async {
    final previous = state[metric]!;
    final rangeDays = days ?? previous.rangeDays;
    final shop = ref.read(selectedShopProvider);
    if (shop == null) {
      _replace(metric, DrillDownState(
        status: DrillDownStatus.error,
        metric: metric,
        rangeDays: rangeDays,
        message: 'No shop selected',
      ));
      return;
    }
    _replace(metric, DrillDownState.loading(metric, rangeDays: rangeDays));
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      if (metric == DrillDownMetric.views) {
        final series = await _repo.fetchViewsSeries(shop.id, token,
            days: rangeDays);
        // Hourly supports up to 90 trailing days on the backend.
        final hourly = await _repo.fetchHourly(shop.id, token,
            days: rangeDays > 90 ? 90 : rangeDays);
        _replace(metric, DrillDownState(
          status: DrillDownStatus.ready,
          metric: metric,
          rangeDays: rangeDays,
          series: series,
          hourly: hourly,
        ));
      } else {
        final series = await _repo.fetchClicksSeries(shop.id, token,
            days: rangeDays);
        final topProducts = await _repo.fetchTopProducts(shop.id, token,
            days: rangeDays, limit: kInsightsMaxTopProducts);
        _replace(metric, DrillDownState(
          status: DrillDownStatus.ready,
          metric: metric,
          rangeDays: rangeDays,
          series: series,
          topProducts: topProducts,
        ));
      }
    } on ApiException catch (e) {
      _replace(metric, DrillDownState(
        status: DrillDownStatus.error,
        metric: metric,
        rangeDays: rangeDays,
        message: e.isForbidden
            ? 'You do not have access to this shop’s reports.'
            : e.message,
      ));
    } catch (_) {
      _replace(metric, DrillDownState(
        status: DrillDownStatus.error,
        metric: metric,
        rangeDays: rangeDays,
        message: 'Could not load the detail view. Please retry.',
      ));
    }
  }

  /// Switches [metric]'s window and reloads.
  Future<void> setRange(DrillDownMetric metric, int days) =>
      load(metric, days: days);

  void _replace(DrillDownMetric metric, DrillDownState next) {
    state = {...state, metric: next};
  }
}
