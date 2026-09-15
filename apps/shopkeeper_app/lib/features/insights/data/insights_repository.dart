import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_providers.dart';
import '../domain/insights_models.dart';

/// Reports / Insights contract for one authorized shop.
///
/// The main screen makes exactly ONE call (`fetchInsights`) — the full report.
/// The granular methods power the KPI **drill-downs**: they unlock parameters
/// the combined report cannot express (a top-products list of up to 50 rows,
/// an hour-of-day distribution over a trailing 90-day window).
abstract class InsightsRepository {
  /// Fetches the complete analytics report for [shopId] over the trailing
  /// [days] window.
  ///
  /// The backend clamps [days] to 1..365 and requires the `dashboard:read`
  /// permission on the shop — an unauthorized shop fails with a 403
  /// [ApiException].
  Future<InsightsBundle> fetchInsights(
    int shopId,
    String token, {
    int days = kInsightsDefaultRange,
  });

  /// Daily shop-view counts (`GET .../analytics/views`).
  Future<List<InsightsPoint>> fetchViewsSeries(
    int shopId,
    String token, {
    int days = kInsightsDefaultRange,
  });

  /// Daily product-click counts (`GET .../analytics/clicks`).
  Future<List<InsightsPoint>> fetchClicksSeries(
    int shopId,
    String token, {
    int days = kInsightsDefaultRange,
  });

  /// Most-viewed products (`GET .../analytics/top-products`) — the drill-down
  /// can request up to [kInsightsMaxTopProducts] rows (the full report ships
  /// the backend default of 10).
  Future<List<TopProduct>> fetchTopProducts(
    int shopId,
    String token, {
    int days = kInsightsDefaultRange,
    int limit = kInsightsMaxTopProducts,
  });

  /// Hour-of-day view distribution (`GET .../analytics/hourly`). The backend
  /// clamps [days] to 1..90 here — wider than the 30-day cap the full report
  /// applies, which is the point of the drill-down.
  Future<List<HourlyPoint>> fetchHourly(
    int shopId,
    String token, {
    int days = kInsightsDefaultRange,
  });
}

class ApiInsightsRepository implements InsightsRepository {
  ApiInsightsRepository(this._api);

  final ApiClient _api;

  @override
  Future<InsightsBundle> fetchInsights(
    int shopId,
    String token, {
    int days = kInsightsDefaultRange,
  }) async {
    final data =
        await _api.get(
              ApiEndpoints.analyticsFull(shopId),
              query: {'days': days},
              token: token,
            )
            as Map<String, dynamic>;
    return InsightsBundle.fromJson(data);
  }

  @override
  Future<List<InsightsPoint>> fetchViewsSeries(
    int shopId,
    String token, {
    int days = kInsightsDefaultRange,
  }) async {
    final data = await _api.get(
      ApiEndpoints.analyticsViews(shopId),
      query: {'days': days},
      token: token,
    ) as Map<String, dynamic>;
    return _series(data['timeseries'], 'views');
  }

  @override
  Future<List<InsightsPoint>> fetchClicksSeries(
    int shopId,
    String token, {
    int days = kInsightsDefaultRange,
  }) async {
    final data = await _api.get(
      ApiEndpoints.analyticsClicks(shopId),
      query: {'days': days},
      token: token,
    ) as Map<String, dynamic>;
    return _series(data['timeseries'], 'clicks');
  }

  @override
  Future<List<TopProduct>> fetchTopProducts(
    int shopId,
    String token, {
    int days = kInsightsDefaultRange,
    int limit = kInsightsMaxTopProducts,
  }) async {
    final data = await _api.get(
      ApiEndpoints.analyticsTopProducts(shopId),
      query: {'days': days, 'limit': limit},
      token: token,
    ) as Map<String, dynamic>;
    return ((data['products'] as List<dynamic>?) ?? const [])
        .whereType<Map>()
        .map((row) => TopProduct.fromJson(row.cast<String, dynamic>()))
        .toList(growable: false);
  }

  @override
  Future<List<HourlyPoint>> fetchHourly(
    int shopId,
    String token, {
    int days = kInsightsDefaultRange,
  }) async {
    final data = await _api.get(
      ApiEndpoints.analyticsHourly(shopId),
      query: {'days': days},
      token: token,
    ) as Map<String, dynamic>;
    return ((data['hourly'] as List<dynamic>?) ?? const [])
        .whereType<Map>()
        .map((row) => HourlyPoint.fromJson(row.cast<String, dynamic>()))
        .toList(growable: false);
  }

  List<InsightsPoint> _series(Object? rows, String valueKey) =>
      ((rows as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((row) => InsightsPoint.fromJson(
                row.cast<String, dynamic>(),
                valueKey,
              ))
          .toList(growable: false);
}

final insightsRepositoryProvider = Provider<InsightsRepository>((ref) {
  return ApiInsightsRepository(ref.watch(apiClientProvider));
});
