import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_providers.dart';
import '../../../../core/network/token_store.dart';
import '../domain/auth_models.dart';
import 'mock_auth_repository.dart';

/// Shopkeeper authentication contract.
///
/// OTP delivery is handled client-side by Firebase Phone Auth, so there is no
/// `sendOtp` here — the controller calls [PhoneAuthService] directly. The
/// `registerWithFirebase` / `loginWithFirebase` methods accept a Firebase ID
/// token that the backend verifies.
abstract class AuthRepository {
  Future<AuthSession> registerWithFirebase({
    required String phoneNumber,
    required String firebaseIdToken,
    required String name,
    String? password,
  });
  Future<AuthSession> loginWithFirebase({
    required String firebaseIdToken,
  });
  Future<AuthSession> loginWithFirebaseAuto({
    required String firebaseIdToken,
    String? name,
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
  Future<AuthSession> registerWithFirebase({
    required String phoneNumber,
    required String firebaseIdToken,
    required String name,
    String? password,
  }) async {
    final data = await _api.post(
      ApiEndpoints.register,
      body: {
        'phone_number': phoneNumber,
        'firebase_id_token': firebaseIdToken,
        'name': name,
        'password': password,
        'device_type': 'mobile',
      },
    ) as Map<String, dynamic>;
    return _persist(data);
  }

  @override
  Future<AuthSession> loginWithFirebase({
    required String firebaseIdToken,
  }) async {
    final data = await _api.post(
      ApiEndpoints.verifyOtp,
      body: {
        'firebase_id_token': firebaseIdToken,
        'device_type': 'mobile',
      },
    ) as Map<String, dynamic>;
    return _persist(data);
  }

  /// Login-or-register via Firebase — auto-creates account if phone is new.
  @override
  Future<AuthSession> loginWithFirebaseAuto({
    required String firebaseIdToken,
    String? name,
  }) async {
    final data = await _api.post(
      ApiEndpoints.firebaseLogin,
      body: {
        'firebase_id_token': firebaseIdToken,
        'name': name,
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

/// Set this to true to use mock auth (no backend / no Firebase required).
/// - Because the app now uses Firebase Phone Auth, mock mode installs a
///   FakePhoneAuthService so OTP works offline on emulators/devices.
/// Set this to false to use real Firebase + backend calls.
const bool kUseMockAuth = true;

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final tokens = ref.watch(tokenStoreProvider);
  
  if (kUseMockAuth) {
    // Use mock repository for testing without backend
    return MockAuthRepository(tokens);
  }
  
  // Use real API repository
  final api = ref.watch(apiClientProvider);
  return ApiAuthRepository(api, tokens);
});
