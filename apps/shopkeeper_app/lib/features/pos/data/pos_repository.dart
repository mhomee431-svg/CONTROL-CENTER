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

  /// Re-validates the stored credentials and re-activates the connector
  /// (`POST .../reconnect`). Returns the server's connected flag.
  ///
  /// Deliberately NOT `/connect`: that endpoint is the first-link action, while
  /// reconnect re-uses the credentials already stored for this connector.
  Future<bool> reconnect(int integrationId, String token);

  /// Rotates the stored vendor credentials (`PUT .../credentials`). Fields left
  /// null are left untouched server-side.
  Future<PosIntegration> updateCredentials(
    int integrationId,
    String token, {
    String? apiKey,
    String? apiSecret,
    String? apiBaseUrl,
  });

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

  /// One connector, freshly read (`GET /shopkeeper/pos/integrations/{id}`).
  Future<PosIntegration> getIntegration(int integrationId, String token);

  /// Pauses/resumes background sync and sets its cadence (`PUT .../schedule`).
  /// Fields left null are left untouched server-side.
  Future<PosIntegration> updateSchedule(
    int integrationId,
    String token, {
    int? syncIntervalMinutes,
    bool? syncEnabled,
  });

  /// Merges vendor-neutral sync settings (`PUT .../config`). Only the keys the
  /// settings carry are touched; everything else keeps the server's value.
  Future<PosIntegration> updateSyncConfig(
    int integrationId,
    String token,
    PosSyncSettings settings,
  );

  /// Terminals mapped to this connector (`GET .../devices`).
  Future<List<PosDevice>> listDevices(int integrationId, String token);

  /// Maps a physical terminal to this connector (`POST .../devices`, 201).
  /// Idempotent: the same identifier refreshes the row, never duplicates it.
  Future<PosDevice> registerDevice(
    int integrationId,
    String token, {
    required String deviceIdentifier,
    String? deviceName,
    String? deviceType,
  });

  /// One job WITH its logs and mapping conflicts
  /// (`GET /shopkeeper/pos/jobs/{id}`).
  Future<PosJobDetail> jobDetail(int jobId, String token);

  /// Re-runs a FAILED job (`POST /shopkeeper/pos/jobs/{id}/retry`). The backend
  /// refuses anything but FAILED with a 409 — e.g. a disconnected connector.
  Future<PosSyncJob> retryJob(int jobId, String token);
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
  Future<bool> reconnect(int integrationId, String token) async {
    // The DEDICATED reconnect endpoint — an earlier version delegated to
    // `/connect`, which is the first-link action, not a re-validation.
    final data = await _api.post(
      ApiEndpoints.posReconnect(integrationId),
      token: token,
    ) as Map<String, dynamic>;
    return data['connected'] as bool? ?? false;
  }

  @override
  Future<PosIntegration> updateCredentials(
    int integrationId,
    String token, {
    String? apiKey,
    String? apiSecret,
    String? apiBaseUrl,
  }) async {
    final data = await _api.put(
      ApiEndpoints.posCredentials(integrationId),
      body: {
        'api_key': ?apiKey,
        'api_secret': ?apiSecret,
        'api_base_url': ?apiBaseUrl,
      },
      token: token,
    ) as Map<String, dynamic>;
    return PosIntegration.fromJson(data);
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

  @override
  Future<PosIntegration> getIntegration(int integrationId, String token) async {
    final data = await _api.get(
      ApiEndpoints.posIntegration(integrationId),
      token: token,
    ) as Map<String, dynamic>;
    return PosIntegration.fromJson(data);
  }

  @override
  Future<PosIntegration> updateSchedule(
    int integrationId,
    String token, {
    int? syncIntervalMinutes,
    bool? syncEnabled,
  }) async {
    final data = await _api.put(
      ApiEndpoints.posSchedule(integrationId),
      body: {
        'sync_interval_minutes': ?syncIntervalMinutes,
        'sync_enabled': ?syncEnabled,
      },
      token: token,
    ) as Map<String, dynamic>;
    return PosIntegration.fromJson(data);
  }

  @override
  Future<PosIntegration> updateSyncConfig(
    int integrationId,
    String token,
    PosSyncSettings settings,
  ) async {
    final data = await _api.put(
      ApiEndpoints.posConfig(integrationId),
      body: {'config': settings.toRequest()},
      token: token,
    ) as Map<String, dynamic>;
    return PosIntegration.fromJson(data);
  }

  @override
  Future<List<PosDevice>> listDevices(int integrationId, String token) async {
    final data = await _api.get(
      ApiEndpoints.posDevices(integrationId),
      token: token,
    ) as Map<String, dynamic>;
    return PosDevice.listFrom(data['devices']);
  }

  @override
  Future<PosDevice> registerDevice(
    int integrationId,
    String token, {
    required String deviceIdentifier,
    String? deviceName,
    String? deviceType,
  }) async {
    final data = await _api.post(
      ApiEndpoints.posDevices(integrationId),
      body: {
        'device_identifier': deviceIdentifier,
        'device_name': ?deviceName,
        'device_type': ?deviceType,
      },
      token: token,
    ) as Map<String, dynamic>;
    return PosDevice.fromJson(data);
  }

  @override
  Future<PosJobDetail> jobDetail(int jobId, String token) async {
    final data = await _api.get(
      ApiEndpoints.posJobDetail(jobId),
      token: token,
    ) as Map<String, dynamic>;
    return PosJobDetail.fromJson(data);
  }

  @override
  Future<PosSyncJob> retryJob(int jobId, String token) async {
    final data = await _api.post(
      ApiEndpoints.posJobRetry(jobId),
      token: token,
    ) as Map<String, dynamic>;
    return PosSyncJob.fromJson(data);
  }
}

final posRepositoryProvider = Provider<PosRepository>((ref) {
  return ApiPosRepository(ref.watch(apiClientProvider));
});
