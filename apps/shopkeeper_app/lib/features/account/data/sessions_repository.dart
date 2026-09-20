import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_providers.dart';
import '../domain/device_session.dart';

/// Session/device contract for the signed-in shopkeeper.
///
/// Implemented by [ApiSessionsRepository] against the shopkeeper-scoped
/// `/shopkeeper/auth/sessions` routes, so this app never reaches into the
/// generic `/auth/*` module (see `api_endpoints.dart`).
abstract class SessionsRepository {
  /// Active sign-in sessions, most recent activity first.
  Future<List<DeviceSession>> fetchSessions(String token);

  /// Revokes one session (device). The backend scopes the lookup to the caller,
  /// so an unknown/already-revoked id fails with 404 rather than touching
  /// another account's session.
  Future<void> revokeSession(String sessionId, String token);
}

class ApiSessionsRepository implements SessionsRepository {
  ApiSessionsRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<DeviceSession>> fetchSessions(String token) async {
    final data = await _api.get(ApiEndpoints.sessions, token: token);
    return DeviceSession.listFrom(data);
  }

  @override
  Future<void> revokeSession(String sessionId, String token) async {
    await _api.delete(ApiEndpoints.session(sessionId), token: token);
  }
}

final sessionsRepositoryProvider = Provider<SessionsRepository>(
  (ref) => ApiSessionsRepository(ref.watch(apiClientProvider)),
);