import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_providers.dart';
import '../domain/pos_models.dart';

/// POS connector contract for one authorized shop.
abstract class PosRepository {
  /// Vendor adapter catalogue (`GET /shopkeeper/pos/providers`).
  Future<List<PosProviderInfo>> listProviders(String token);

  /// Integrations for the shop (`GET /shopkeeper/pos/integrations?shop_id=`).
  Future<List<PosIntegration>> listIntegrations(int shopId, String token);

  /// Registers a new connector (`POST /shopkeeper/pos/register`).
  Future<PosIntegration> register(
    int shopId,
    String providerCode,
    String token, {
    String integrationType = 'API',
  });

  /// Validates credentials and flips the integration to ACTIVE
  /// (`POST .../connect`). Returns the server's connected flag — a `false`
  /// here means the provider refused the credentials (not a network error).
  Future<bool> connect(int integrationId, String token);

  /// Stops scheduled syncs (`POST .../disconnect`).
  Future<PosIntegration> disconnect(int integrationId, String token);

  /// Queues a manual sync job (`POST .../sync`, 202).
  Future<PosSyncJob> triggerSync(
    int integrationId,
    String token, {
    String syncType = 'FULL',
  });

  /// Aggregated dashboard payload (`GET .../status`) — integration plus the
  /// newest sync job when one exists.
  Future<PosIntegration> status(int integrationId, String token);

  /// Recent sync jobs, newest first (`GET .../jobs?limit=`).
  Future<List<PosSyncJob>> listJobs(
    int integrationId,
    String token, {
    int limit = 20,
  });
}

class ApiPosRepository implements PosRepository {
  ApiPosRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<PosProviderInfo>> listProviders(String token) async {
    final data = await _api.get(ApiEndpoints.posProviders, token: token)
        as Map<String, dynamic>;
    return PosProviderInfo.listFrom(data['providers']);
  }

  @override
  Future<List<PosIntegration>> listIntegrations(
    int shopId,
    String token,
  ) async {
    final data = await _api.get(
      ApiEndpoints.posIntegrations,
      query: {'shop_id': shopId},
      token: token,
    ) as Map<String, dynamic>;
    return PosIntegration.listFromList(data['integrations']);
  }

  @override
  Future<PosIntegration> register(
    int shopId,
    String providerCode,
    String token, {
    String integrationType = 'API',
  }) async {
    final data = await _api.post(
      ApiEndpoints.posRegister,
      body: {
        'shop_id': shopId,
        'provider_code': providerCode,
        'integration_type': integrationType,
      },
      token: token,
    ) as Map<String, dynamic>;
    return PosIntegration.fromJson(data);
  }

  @override
  Future<bool> connect(int integrationId, String token) async {
    final data = await _api.post(
      ApiEndpoints.posConnect(integrationId),
      token: token,
    ) as Map<String, dynamic>;
    return data['connected'] as bool? ?? false;
  }

  @override
  Future<PosIntegration> disconnect(int integrationId, String token) async {
    final data = await _api.post(
      ApiEndpoints.posDisconnect(integrationId),
      token: token,
    ) as Map<String, dynamic>;
    return PosIntegration.fromJson(data);
  }

  @override
  Future<PosSyncJob> triggerSync(
    int integrationId,
    String token, {
    String syncType = 'FULL',
  }) async {
    final data = await _api.post(
      ApiEndpoints.posSync(integrationId),
      body: {'sync_type': syncType},
      token: token,
    ) as Map<String, dynamic>;
    return PosSyncJob.fromJson(data);
  }

  @override
  Future<PosIntegration> status(int integrationId, String token) async {
    final data = await _api.get(
      ApiEndpoints.posStatus(integrationId),
      token: token,
    ) as Map<String, dynamic>;
    return PosIntegration.fromJson(data);
  }

  @override
  Future<List<PosSyncJob>> listJobs(
    int integrationId,
    String token, {
    int limit = 20,
  }) async {
    final data = await _api.get(
      ApiEndpoints.posJobs(integrationId),
      query: {'limit': limit},
      token: token,
    ) as Map<String, dynamic>;
    return PosSyncJob.listFrom(data['jobs']);
  }
}

final posRepositoryProvider = Provider<PosRepository>((ref) {
  return ApiPosRepository(ref.watch(apiClientProvider));
});
