import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failures.dart';
import '../../../core/storage/secure_storage_service.dart';
import 'auth_repository.dart';

/// Application-level device metadata sent with auth requests.
const authAppVersion = '1.0.0';
const authDeviceName = 'Hyperlocal App';
const authDeviceType = 'mobile';

/// AuthService coordinates the repository (data) with secure storage
/// (session persistence). The UI/controller talks only to this service,
/// never directly to storage or the repository.
///
/// This abstraction is the seam that allows the future backend to replace
/// the mock repository without any UI changes.
class AuthService {
  final AuthRepository _repository;
  final SecureStorageService _storage;

  AuthService(this._repository, this._storage);

  Future<void> sendOtp(String phoneNumber) => _repository.sendOtp(phoneNumber);

  Future<AuthSession> verifyOtp({
    required String phoneNumber,
    required String otpCode,
    required bool isNewUser,
    String? name,
  }) async {
    final deviceId = await _getOrCreateDeviceId();

    final AuthResult result;
    if (isNewUser) {
      result = await _repository.register(
        phoneNumber: phoneNumber,
        otpCode: otpCode,
        name: (name != null && name.trim().isNotEmpty)
            ? name.trim()
            : 'Customer',
        deviceId: deviceId,
        deviceName: authDeviceName,
        deviceType: authDeviceType,
        appVersion: authAppVersion,
      );
    } else {
      result = await _repository.verifyOtp(
        phoneNumber: phoneNumber,
        otpCode: otpCode,
        deviceId: deviceId,
        deviceName: authDeviceName,
        deviceType: authDeviceType,
        appVersion: authAppVersion,
      );
    }

    final session = AuthSession.fromAuthResult(result);
    await _persistSession(session);
    return session;
  }

  /// Sign in with Google, persist the resulting backend session and return it.
  ///
  /// The repository/native layer obtains the Firebase ID token; the backend
  /// verifies it before issuing our session tokens.
  Future<AuthSession> signInWithGoogle() async {
    final deviceId = await _getOrCreateDeviceId();
    final result = await _repository.signInWithGoogle(
      deviceId: deviceId,
      deviceName: authDeviceName,
      deviceType: authDeviceType,
      appVersion: authAppVersion,
    );
    final session = AuthSession.fromAuthResult(result);
    await _persistSession(session);
    return session;
  }

  /// Persist all auth session data securely.
  Future<void> _persistSession(AuthSession session) async {
    await _storage.saveToken(session.accessToken);
    if (session.refreshToken.isNotEmpty) {
      await _storage.saveRefreshToken(session.refreshToken);
    }
    if (session.sessionId.isNotEmpty) {
      await _storage.saveSessionId(session.sessionId);
    }
    await _storage.setGuestMode(false);
  }

  /// Restore the persisted session on app startup.
  Future<AuthSession?> restoreSession() async {
    final token = await _storage.getToken();
    final sessionId = await _storage.getSessionId();
    if (token == null ||
        token.isEmpty ||
        sessionId == null ||
        sessionId.isEmpty) {
      return null;
    }

    final refreshToken = await _storage.getRefreshToken();
    final deviceId = await _storage.getDeviceId();

    return AuthSession(
      accessToken: token,
      refreshToken: refreshToken ?? '',
      sessionId: sessionId,
      userId: null,
      phoneNumber: null,
      name: null,
      role: null,
      deviceId: deviceId,
    );
  }

  Future<String> _getOrCreateDeviceId() async {
    var deviceId = await _storage.getDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = _generateDeviceId();
      await _storage.saveDeviceId(deviceId);
    }
    return deviceId;
  }

  Future<String?> refreshAccessToken() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return null;
    }
    final deviceId = await _storage.getDeviceId();
    final result = await _repository.refreshToken(
      refreshToken,
      deviceId: deviceId,
    );

    // The backend ROTATES the refresh token on every use (with reuse
    // detection). Persisting only the access token here would leave a stale
    // refresh token on the device, and the next refresh would be rejected —
    // so both tokens must be re-saved.
    await _storage.saveToken(result.accessToken);
    if (result.refreshToken.isNotEmpty) {
      await _storage.saveRefreshToken(result.refreshToken);
    }
    if (result.sessionId.isNotEmpty) {
      await _storage.saveSessionId(result.sessionId);
    }
    return result.accessToken;
  }

  Future<void> logout() async {
    final refreshToken = await _storage.getRefreshToken();
    final sessionId = await _storage.getSessionId();
    try {
      await _repository.logout(
        refreshToken: refreshToken,
        sessionId: sessionId,
      );
    } catch (_) {
      // Even if backend revocation fails, clear local state.
    }
    await _storage.clearAll();
  }

  /// Clears the local session WITHOUT contacting the server.
  ///
  /// Used after an unrecoverable auth failure (401 + failed refresh): the
  /// server-side session is already gone, so only device state needs clearing.
///
/// WHY NOT `_storage.clearAll()`
/// ---------------------------
/// This used to call `clearAll()`, which wipes EVERY secure-storage key —
/// including `has_onboarded`. The consequence was invisible and bad: an
/// ordinary token expiry tripped the router's `onboardingCompleted == null`
/// gate and sent the customer back through the whole first-launch tour.
/// Expiring a token is not a reason to make someone re-onboard, and a
/// returning customer who suddenly sees the welcome carousel concludes the app
/// lost their account.
///
/// Only the SESSION keys are deleted. Everything describing the DEVICE or the
/// customer's preferences survives an expiry: `has_onboarded`, settings,
/// cached addresses. The interceptor already removed these three keys by the
/// time this runs, so repeating it is idempotent — and it makes this method
/// safe to call on its own.
  Future<void> clearLocalSession() async {
  await _storage.deleteToken();
  await _storage.deleteRefreshToken();
  await _storage.deleteSessionId();
  await _storage.setGuestMode(false);
}

  Future<bool> isGuestMode() => _storage.isGuestMode();

  Future<void> setGuestMode(bool value) => _storage.setGuestMode(value);

  /// Determine if this is a first-time user by checking a persisted flag.
  Future<bool> isFirstTimeUser() async {
    final value = await _storage.read(key: 'has_onboarded');
    return value != 'true';
  }

  Future<void> markOnboarded() async {
    await _storage.write(key: 'has_onboarded', value: 'true');
  }

  String _generateDeviceId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final random = DateTime.now().microsecondsSinceEpoch.toString();
    return 'dev_${timestamp}_$random';
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(
    ref.watch(authRepositoryProvider),
    ref.watch(secureStorageProvider),
  );
});

/// Map any thrown Failure to a user-friendly message.
String authErrorMessage(Object error) {
  if (error is Failure) return error.message;
  return 'Something went wrong. Please try again.';
}
