import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_providers.dart';
import '../../../../core/network/token_store.dart';
import '../domain/auth_models.dart';
import 'mock_auth_repository.dart';

/// Shopkeeper authentication contract — simple phone + password login.
abstract class AuthRepository {
  /// Simple registration: phone + password.
  Future<AuthSession> registerWithPassword({
    required String name,
    required String phoneNumber,
    required String password,
  });

  Future<AuthSession> loginWithPassword({
    required String identifier,
    required String password,
  });

  /// Restores a stored session; returns null when none is valid.
  Future<AuthSession?> restoreSession();
  Future<void> logout();
  Future<void> forgotPassword(String identifier);
  Future<void> resetPassword({required String token, required String newPassword});
}

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStore _tokens;

  @override
  Future<AuthSession> registerWithPassword({
    required String name,
    required String phoneNumber,
    required String password,
  }) async {
    final data = await _api.post(
      ApiEndpoints.register,
      body: {
        'phone_number': phoneNumber,
        'name': name,
        'password': password,
        'device_type': 'mobile',
      },
    ) as Map<String, dynamic>;
    return _persist(data);
  }

  @override
  Future<AuthSession> loginWithPassword({
    required String identifier,
    required String password,
  }) async {
    final data = await _api.post(
      ApiEndpoints.login,
      body: {
        'identifier': identifier,
        'password': password,
        'device_type': 'mobile',
      },
    ) as Map<String, dynamic>;
    return _persist(data);
  }

  @override
  Future<void> forgotPassword(String identifier) async {
    await _api.post(
      ApiEndpoints.forgotPassword,
      body: {'identifier': identifier},
    );
  }

  @override
  Future<void> resetPassword({required String token, required String newPassword}) async {
    await _api.post(
      ApiEndpoints.resetPassword,
      body: {'token': token, 'new_password': newPassword},
    );
  }

  Future<AuthSession> _persist(Map<String, dynamic> data) async {
    final access = data['access_token'] as String?;
    final refresh = data['refresh_token'] as String?;
    final sessionId = data['session_id'] as String?;
    final businessId = (data['business_id'] ??
            (data['user'] as Map?)?['business_id']) as String?;
    if (access != null && refresh != null) {
      await _tokens.saveTokens(accessToken: access, refreshToken: refresh);
    }
    if (sessionId != null) await _tokens.saveSessionId(sessionId);
    if (businessId != null && businessId.isNotEmpty) {
      await _tokens.saveBusinessId(businessId);
    }
    return AuthSession(
      user: ShopkeeperUser.fromJson(
          ((data['user'] as Map?)?.cast<String, dynamic>()) ?? const {}),
      shops: ((data['shops'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => ShopSummary.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }

  @override
  Future<AuthSession?> restoreSession() async {
    final access = await _tokens.readAccessToken();
    if (access == null || access.isEmpty) return null;
    try {
      final data =
          await _api.get(ApiEndpoints.me, token: access) as Map<String, dynamic>;
      return AuthSession(
        user: ShopkeeperUser.fromJson(data),
        shops: ((data['shops'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => ShopSummary.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false),
      );
    } on ApiException catch (e) {
      // Invalid/expired stored token → clean slate.
      if (e.isUnauthorized) await _tokens.clearAll();
      return null;
    } catch (_) {
      // Offline / transient — do not wipe a possibly valid session.
      return null;
    }
  }

  @override
  Future<void> logout() async {
    try {
      final access = await _tokens.readAccessToken();
      await _api.post(ApiEndpoints.logout, body: {}, token: access);
    } on ApiException catch (_) {
      // Server-side revocation failures must not block local sign-out.
    } finally {
      await _tokens.clearAll();
    }
  }
}

/// Set this to true to use the mock auth repository (no backend required),
/// useful for offline development on emulators/devices.
const bool kUseMockAuth = false;

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final tokens = ref.watch(tokenStoreProvider);

  if (kUseMockAuth) {
    return MockAuthRepository(tokens);
  }

  final api = ref.watch(apiClientProvider);
  return ApiAuthRepository(api, tokens);
});