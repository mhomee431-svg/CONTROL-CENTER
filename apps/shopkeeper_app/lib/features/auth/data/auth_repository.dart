import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_providers.dart';
import '../../../core/network/token_store.dart';
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

  /// Firebase Google Sign-In: verify a Firebase ID token with the backend
  /// (Firebase Admin SDK) and return the session. Auto-registers ONE
  /// shopkeeper profile on first sign-in.
  Future<AuthSession> firebaseLogin({
    required String firebaseIdToken,
    String? name,
    String? email,
    String? photoUrl,
  });

  /// Updates the current user's profile (name; phone accepted for contract
  /// compatibility — the backend profile endpoint manages name/email) and
  /// returns the refreshed session.
  Future<AuthSession> updateProfile({required String name, String? phoneNumber});

  // ── Debug helpers for verbose login flow logging ──────────────────────
  Future<String?> debugReadToken();
  Future<String?> debugReadUserId();
  Future<bool> debugIsLoggedIn();
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
    final userId = (data['user_id'] ??
            (data['user'] as Map?)?['id'] ??
            (data['id']))?.toString();

    debugPrint('  ├─ _persist(): Saving session to local storage...');

    if (access != null && refresh != null) {
      debugPrint('  │  ├─ Saving access_token + refresh_token + jwt_token...');
      await _tokens.saveTokens(accessToken: access, refreshToken: refresh);
      debugPrint('  │  │  ✓ Tokens saved (${access.length} chars)');
    } else {
      debugPrint('  │  ├─ ⚠ access or refresh token is null, skipping saveTokens');
    }

    if (sessionId != null) {
      debugPrint('  │  ├─ Saving session_id...');
      await _tokens.saveSessionId(sessionId);
      debugPrint('  │  │  ✓ Session ID saved');
    }

    if (businessId != null && businessId.isNotEmpty) {
      debugPrint('  │  ├─ Saving business_id...');
      await _tokens.saveBusinessId(businessId);
      debugPrint('  │  │  ✓ Business ID saved: $businessId');
    }

    // Save user-specified session keys
    if (userId != null && userId.isNotEmpty && userId != 'null') {
      debugPrint('  │  ├─ Saving user_id...');
      await _tokens.saveUserId(userId);
      debugPrint('  │  │  ✓ User ID saved: $userId');
    }

    debugPrint('  │  ├─ Setting is_logged_in = true...');
    await _tokens.setLoggedIn(true);
    debugPrint('  │  └─ ✓ Login state saved');

    final session = AuthSession(
      user: ShopkeeperUser.fromJson(
          ((data['user'] as Map?)?.cast<String, dynamic>()) ?? const {}),
      shops: ((data['shops'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => ShopSummary.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false),
    );

    debugPrint('  └─ _persist() complete: user=${session.user.id}, shops=${session.shops.length}');
    return session;
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

  @override
  Future<AuthSession> firebaseLogin({
    required String firebaseIdToken,
    String? name,
    String? email,
    String? photoUrl,
  }) async {
    final requestBody = {
      'firebase_id_token': firebaseIdToken,
      if (name != null && name.isNotEmpty) 'name': name,
      if (email != null && email.isNotEmpty) 'email': email,
      if (photoUrl != null && photoUrl.isNotEmpty) 'photo_url': photoUrl,
    };
    debugPrint('  ├─ API URL: ${ApiEndpoints.firebaseLogin}');
    debugPrint('  ├─ Request body keys: ${requestBody.keys.toList()}');
    debugPrint('  ├─ Token length: ${firebaseIdToken.length} chars');
    debugPrint('  ├─ Name: ${name ?? "null"}');
    debugPrint('  ├─ Email: ${email ?? "null"}');
    debugPrint('  └─ Photo URL: ${photoUrl != null ? "present" : "null"}');

    final data = await _api.post(
      ApiEndpoints.firebaseLogin,
      body: requestBody,
    ) as Map<String, dynamic>;

    debugPrint('  ├─ Response received');
    debugPrint('  ├─ Response keys: ${data.keys.toList()}');
    debugPrint('  ├─ access_token: ${data['access_token'] != null ? "present (${(data['access_token'] as String).length} chars)" : "null"}');
    debugPrint('  ├─ refresh_token: ${data['refresh_token'] != null ? "present" : "null"}');
    debugPrint('  ├─ session_id: ${data['session_id'] ?? "null"}');
    debugPrint('  └─ user_id: ${data['user_id'] ?? (data['user'] as Map?)?['id'] ?? "null"}');

    return _persist(data);
  }

  // ── Debug helpers ───────────────────────────────────────────────────

  @override
  Future<String?> debugReadToken() async {
    return _tokens.readAccessToken();
  }

  @override
  Future<String?> debugReadUserId() async {
    return _tokens.readUserId();
  }

  @override
  Future<bool> debugIsLoggedIn() async {
    return _tokens.isLoggedIn();
  }

  @override
  Future<AuthSession> updateProfile({
    required String name,
    String? phoneNumber,
  }) async {
    final access = await _tokens.readAccessToken();
    await _api.put(ApiEndpoints.profile, body: {'name': name}, token: access);
    final session = await restoreSession();
    if (session == null) {
      throw const ApiException(
        message: 'Profile updated but the session could not be restored',
        errorCode: 'SESSION_RESTORE_FAILED',
      );
    }
    return session;
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