import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_providers.dart';
import '../domain/dashboard_models.dart';

/// Dashboard contract for one authorized shop.
abstract class DashboardRepository {
  Future<DashboardData> fetchDashboard(int shopId, String token);
}

class ApiDashboardRepository implements DashboardRepository {
  ApiDashboardRepository(this._api);

  final ApiClient _api;

  @override
  Future<DashboardData> fetchDashboard(int shopId, String token) async {
    final data = await _api.get('/api/v1/shopkeeper/shops/$shopId/dashboard',
        token: token) as Map<String, dynamic>;
    return DashboardData.fromJson(data);
  }
}

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return ApiDashboardRepository(ref.watch(apiClientProvider));
});
