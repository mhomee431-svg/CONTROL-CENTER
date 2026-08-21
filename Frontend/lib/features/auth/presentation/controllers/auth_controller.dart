import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/storage/secure_storage_service.dart';
import '../../domain/auth_repository.dart';
import '../../../../core/error/failures.dart';

enum AuthStatus { initial, loading, authenticated, guest, unauthenticated, error }

class AuthState {
  final AuthStatus status;
  final String? errorMessage;

  const AuthState({required this.status, this.errorMessage});

  factory AuthState.initial() => const AuthState(status: AuthStatus.initial);
  factory AuthState.loading() => const AuthState(status: AuthStatus.loading);
  factory AuthState.authenticated() => const AuthState(status: AuthStatus.authenticated);
  factory AuthState.guest() => const AuthState(status: AuthStatus.guest);
  factory AuthState.unauthenticated() => const AuthState(status: AuthStatus.unauthenticated);
  factory AuthState.error(String msg) => AuthState(status: AuthStatus.error, errorMessage: msg);
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    return AuthState.initial();
  }

  Future<void> checkAuthStatus() async {
    state = AuthState.loading();
    final storage = ref.read(secureStorageProvider);
    final token = await storage.getToken();
    if (token != null) {
      state = AuthState.authenticated();
    } else {
      final isGuest = await storage.isGuestMode();
      state = isGuest ? AuthState.guest() : AuthState.unauthenticated();
    }
  }

  Future<bool> sendOtp(String phoneNumber) async {
    state = AuthState.loading();
    try {
      final repository = ref.read(authRepositoryProvider);
      await repository.sendOtp(phoneNumber);
      state = AuthState.unauthenticated(); // Ready for OTP
      return true;
    } catch (e) {
      state = AuthState.error(e is Failure ? e.message : 'Failed to send OTP');
      return false;
    }
  }

  Future<bool> verifyOtp(String phoneNumber, String otp) async {
    state = AuthState.loading();
    try {
      final repository = ref.read(authRepositoryProvider);
      final storage = ref.read(secureStorageProvider);

      // Get or generate a stable device ID for session tracking
      var deviceId = await storage.getDeviceId();
      if (deviceId == null || deviceId.isEmpty) {
        deviceId = _generateDeviceId();
        await storage.saveDeviceId(deviceId);
      }

      final result = await repository.verifyOtp(
        phoneNumber: phoneNumber,
        otpCode: otp,
        deviceId: deviceId,
        deviceName: 'Hyperlocal App',
        deviceType: 'mobile',
        appVersion: '1.0.0',
      );

      // Store all auth session data securely
      await storage.saveToken(result.accessToken);
      if (result.refreshToken.isNotEmpty) {
        await storage.saveRefreshToken(result.refreshToken);
      }
      if (result.sessionId.isNotEmpty) {
        await storage.saveSessionId(result.sessionId);
      }
      await storage.setGuestMode(false);
      state = AuthState.authenticated();
      return true;
    } catch (e) {
      state = AuthState.error(e is Failure ? e.message : 'Invalid OTP');
      return false;
    }
  }

  /// Generate a stable device identifier for session tracking.
  String _generateDeviceId() {
    // Use a combination of timestamp and random values
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final random = DateTime.now().microsecondsSinceEpoch.toString();
    return 'dev_${timestamp}_$random';
  }

  Future<void> continueAsGuest() async {
    state = AuthState.loading();
    final storage = ref.read(secureStorageProvider);
    await storage.setGuestMode(true);
    state = AuthState.guest();
  }

  Future<void> logout() async {
    state = AuthState.loading();
    try {
      final repository = ref.read(authRepositoryProvider);
      final storage = ref.read(secureStorageProvider);

      // Attempt to revoke the session on the backend
      final refreshToken = await storage.getRefreshToken();
      final sessionId = await storage.getSessionId();
      try {
        await repository.logout(
          refreshToken: refreshToken,
          sessionId: sessionId,
        );
      } catch (_) {
        // Even if backend revocation fails, clear local state
      }

      await storage.clearAll();
      state = AuthState.unauthenticated();
    } catch (e) {
      state = AuthState.unauthenticated();
    }
  }

  Future<bool> refreshAccessToken() async {
    try {
      final repository = ref.read(authRepositoryProvider);
      final storage = ref.read(secureStorageProvider);
      final refreshToken = await storage.getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        state = AuthState.unauthenticated();
        return false;
      }

      final deviceId = await storage.getDeviceId();
      final newAccessToken = await repository.refreshToken(
        refreshToken,
        deviceId: deviceId,
      );
      if (newAccessToken != null) {
        await storage.saveToken(newAccessToken);
        state = AuthState.authenticated();
        return true;
      }

      state = AuthState.unauthenticated();
      return false;
    } catch (e) {
      state = AuthState.unauthenticated();
      return false;
    }
  }
}