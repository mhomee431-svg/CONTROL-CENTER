import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_providers.dart';
import '../../../../core/network/token_store.dart';
import '../domain/auth_models.dart';

/// Shopkeeper authentication contract.
abstract class AuthRepository {
  Future<void> sendOtp(String phoneNumber);
  Future<AuthSession> register({
    required String phoneNumber,
    required String otp,
    required String name,
  });
  Future<AuthSession> login({
    required String phoneNumber,
    required String otp,
  });

  /// Restores a stored session; returns null when none is valid.
  Future<AuthSession?> restoreSession();
  Future<void> logout();
}

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStore _tokens;

  @override
  Future<void> sendOtp(String phoneNumber) async {
    await _api.post(ApiEndpoints.sendOtp, body: {'phone_number': phoneNumber});
  }

  @override
  Future<AuthSession> register({
    required String phoneNumber,
    required String otp,
    required String name,
  }) async {
    final data = await _api.post(
      ApiEndpoints.register,
      body: {
        'phone_number': phoneNumber,
        'otp': otp,
        'name': name,
        'device_type': 'mobile',
      },
    ) as Map<String, dynamic>;
    return _persist(data);
  }

  @override
  Future<AuthSession> login({
    required String phoneNumber,
    required String otp,
  }) async {
    final data = await _api.post(
      ApiEndpoints.login,
      body: {
        'phone_number': phoneNumber,
        'otp': otp,
        'device_type': 'mobile',
      },
    ) as Map<String, dynamic>;
    return _persist(data);
  }

  Future<AuthSession> _persist(Map<String, dynamic> data) async {
    final access = data['access_token'] as String?;
    final refresh = data['refresh_token'] as String?;
    final sessionId = data['session_id'] as String?;
    if (access != null && refresh != null) {
      await _tokens.saveTokens(accessToken: access, refreshToken: refresh);
    }
    if (sessionId != null) await _tokens.saveSessionId(sessionId);
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

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  final tokens = ref.watch(tokenStoreProvider);
  return ApiAuthRepository(api, tokens);
});
