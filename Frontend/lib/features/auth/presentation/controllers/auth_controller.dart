import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/auth_service.dart';

enum AuthStatus {
  initial,
  loading,
  otpSent,
  authenticated,
  guest,
  unauthenticated,
  sessionExpired,
  error,
}

class AuthState {
  final AuthStatus status;
  final String? errorMessage;
  final bool isFirstTimeUser;
  final String? phoneNumber;

  const AuthState({
    required this.status,
    this.errorMessage,
    this.isFirstTimeUser = false,
    this.phoneNumber,
  });

  factory AuthState.initial() => const AuthState(status: AuthStatus.initial);
  factory AuthState.loading() => const AuthState(status: AuthStatus.loading);
  factory AuthState.otpSent(String phone) =>
      AuthState(status: AuthStatus.otpSent, phoneNumber: phone);
  factory AuthState.authenticated() =>
      const AuthState(status: AuthStatus.authenticated);
  factory AuthState.guest() => const AuthState(status: AuthStatus.guest);
  factory AuthState.unauthenticated() =>
      const AuthState(status: AuthStatus.unauthenticated);
  factory AuthState.sessionExpired() =>
      const AuthState(status: AuthStatus.sessionExpired);
  factory AuthState.error(String msg) =>
      AuthState(status: AuthStatus.error, errorMessage: msg);
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    return AuthState.initial();
  }

  /// Restore a persisted session on app startup.
  Future<bool> checkAuthStatus() async {
    state = AuthState.loading();
    try {
      final service = ref.read(authServiceProvider);
      final session = await service.restoreSession();

      if (session != null && session.isValid) {
        // Attempt a silent refresh to validate the token.
        // If refresh fails, fall back to logged-out state.
        try {
          final newToken = await service.refreshAccessToken();
          if (newToken != null) {
            state = AuthState.authenticated();
            return true;
          }
        } catch (_) {
          // Token refresh failed -> session is invalid/expired.
        }
        state = AuthState.sessionExpired();
        return false;
      }

      final isGuest = await service.isGuestMode();
      state = isGuest ? AuthState.guest() : AuthState.unauthenticated();
      return false;
    } catch (e) {
      state = AuthState.error(authErrorMessage(e));
      return false;
    }
  }

  Future<bool> sendOtp(String phoneNumber) async {
    state = AuthState.loading();
    try {
      final service = ref.read(authServiceProvider);
      await service.sendOtp(phoneNumber);
      state = AuthState.otpSent(phoneNumber);
      return true;
    } catch (e) {
      state = AuthState.error(authErrorMessage(e));
      return false;
    }
  }

  Future<bool> verifyOtp({
    required String phoneNumber,
    required String otpCode,
    required bool isNewUser,
  }) async {
    state = AuthState.loading();
    try {
      final service = ref.read(authServiceProvider);
      final session = await service.verifyOtp(
        phoneNumber: phoneNumber,
        otpCode: otpCode,
        isNewUser: isNewUser,
      );

      // Mark that onboarding has been seen for this successful login.
      if (session.isValid) {
        await service.markOnboarded();
      }

      state = AuthState.authenticated();
      return true;
    } catch (e) {
      state = AuthState.error(authErrorMessage(e));
      return false;
    }
  }

  Future<void> continueAsGuest() async {
    state = AuthState.loading();
    final service = ref.read(authServiceProvider);
    await service.setGuestMode(true);
    state = AuthState.guest();
  }

  Future<void> logout() async {
    state = AuthState.loading();
    try {
      final service = ref.read(authServiceProvider);
      await service.logout();
    } catch (_) {
      // Even if logout fails server-side, transition to signed-out.
    }
    state = AuthState.unauthenticated();
  }

  /// Signs the customer out locally after an unrecoverable auth failure
  /// (a 401 whose refresh also failed — the server session is gone).
  ///
  /// The router reacts to [AuthStatus.sessionExpired] by returning the
  /// customer to the Welcome screen; no UI changes are needed here.
  Future<void> handleSessionExpired() async {
    try {
      await ref.read(authServiceProvider).clearLocalSession();
    } catch (_) {
      // Storage clearing must never block the sign-out transition.
    }
    state = AuthState.sessionExpired();
  }

  Future<bool> refreshAccessToken() async {
    try {
      final service = ref.read(authServiceProvider);
      final newToken = await service.refreshAccessToken();
      if (newToken != null) {
        state = AuthState.authenticated();
        return true;
      }
      state = AuthState.unauthenticated();
      return false;
    } catch (e) {
      state = AuthState.sessionExpired();
      return false;
    }
  }
}