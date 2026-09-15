import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_providers.dart';
import '../domain/insights_models.dart';

/// Reports / Insights contract for one authorized shop.
///
/// The backend computes every metric from the real analytics event stream, so
/// there is exactly ONE call to make: the full report for the window.
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
}

final insightsRepositoryProvider = Provider<InsightsRepository>((ref) {
  return ApiInsightsRepository(ref.watch(apiClientProvider));
});
