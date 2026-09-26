import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failures.dart';
import '../../domain/auth_repository.dart';
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

/// Coarse classification of the last auth failure.
///
/// Lets the UI pick the right recovery affordance (e.g. enable "Resend OTP"
/// the moment a code expires) without parsing message strings.
enum AuthErrorKind {
  invalidPhoneNumber,
  invalidOtp,
  expiredOtp,
  rateLimited,
  network,
  cancelled,
  sessionExpired,
  unknown,
}

class AuthState {
  final AuthStatus status;
  final String? errorMessage;
  final bool isFirstTimeUser;
  final String? phoneNumber;

  /// Set when [status] is [AuthStatus.error] — see [AuthErrorKind].
  final AuthErrorKind? errorKind;

  const AuthState({
    required this.status,
    this.errorMessage,
    this.isFirstTimeUser = false,
    this.phoneNumber,
    this.errorKind,
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
  factory AuthState.error(String msg, {AuthErrorKind? kind}) =>
      AuthState(status: AuthStatus.error, errorMessage: msg, errorKind: kind);
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    return AuthState.initial();
  }

  /// Determine the starting auth state on app launch.
  ///
  /// ── Phase 11: guest-first experience ──────────────────────────────
  /// The customer is always treated as a guest on first open. There is
  /// no welcome / login wall — they land directly on the Home screen.
  /// Login (phone OTP) is only prompted later when the customer tries
  /// to perform a write action that requires an account (e.g. shop
  /// ratings). Until then they remain a guest.
  Future<bool> checkAuthStatus() async {
    state = AuthState.loading();
    try {
      final service = ref.read(authServiceProvider);
      final session = await service.restoreSession();

      if (session != null && session.isValid) {
        try {
          final newToken = await service.refreshAccessToken();
          if (newToken != null) {
            state = AuthState.authenticated();
            return true;
          }
        } catch (_) {
          // Token refresh failed -> session is invalid/expired.
        }
        // Session exists but isn't valid anymore — downgrade to guest so
        // the customer can still browse without being shown a login wall.
        state = AuthState.guest();
        return false;
      }

      // No valid session: ensure we're in guest mode so the router sends
      // the customer straight to the Home screen.
      await service.setGuestMode(true);
      state = AuthState.guest();
      return false;
    } catch (e) {
      // Even if anything fails, fall back to guest (never to the
      // welcome screen).
      state = AuthState.guest();
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
      state = AuthState.error(authErrorMessage(e), kind: _errorKindFor(e));
      return false;
    }
  }

  Future<bool> verifyOtp({
    required String phoneNumber,
    required String otpCode,
    required bool isNewUser,
    String? name,
  }) async {
    state = AuthState.loading();
    try {
      final service = ref.read(authServiceProvider);
      final session = await service.verifyOtp(
        phoneNumber: phoneNumber,
        otpCode: otpCode,
        isNewUser: isNewUser,
        name: name,
      );

      // Mark that onboarding has been seen for this successful login.
      if (session.isValid) {
        await service.markOnboarded();
      }

      state = AuthState.authenticated();
      return true;
    } catch (e) {
      state = AuthState.error(authErrorMessage(e), kind: _errorKindFor(e));
      return false;
    }
  }

  /// Sign in with Google and transition to [AuthStatus.authenticated].
  ///
  /// Returns true on success. A user-dismissed Google sheet is not treated as
  /// an error — the previous browsing state is restored silently.
  Future<bool> signInWithGoogle() async {
    final previous = state;
    state = AuthState.loading();
    try {
      final service = ref.read(authServiceProvider);
      final session = await service.signInWithGoogle();

      if (session.isValid) {
        await service.markOnboarded();
      }

      state = AuthState.authenticated();
      return true;
    } on GoogleSignInCancelledFailure {
      state = previous.status == AuthStatus.authenticated
          ? previous
          : AuthState.guest();
      return false;
    } catch (e) {
      state = AuthState.error(authErrorMessage(e), kind: _errorKindFor(e));
      return false;
    }
  }

  /// Abandons an in-flight phone-OTP verification.
  ///
  /// Called when the customer backs out of the OTP screen (cancelled flow):
  /// the pending verification is dropped and the app returns to guest
  /// browsing without any error or "waiting for OTP" state left behind.
  Future<void> cancelOtpVerification() async {
    try {
      await ref.read(phoneAuthServiceProvider).cancelPendingVerification();
      if (state.status != AuthStatus.authenticated) {
        state = AuthState.guest();
      }
    } catch (_) {
      // Best-effort cleanup — must never block navigation back to browsing.
    }
  }

  /// Classify a failure so the UI can pick the right recovery affordance.
  AuthErrorKind _errorKindFor(Object error) {
    if (error is InvalidPhoneNumberFailure) {
      return AuthErrorKind.invalidPhoneNumber;
    }
    if (error is InvalidOtpFailure) return AuthErrorKind.invalidOtp;
    if (error is ExpiredOtpFailure) return AuthErrorKind.expiredOtp;
    if (error is TooManyAttemptsFailure || error is OtpRateLimitFailure) {
      return AuthErrorKind.rateLimited;
    }
    if (error is NetworkFailure) return AuthErrorKind.network;
    if (error is GoogleSignInCancelledFailure) return AuthErrorKind.cancelled;
    if (error is SessionExpiredFailure) return AuthErrorKind.sessionExpired;
    return AuthErrorKind.unknown;
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
  /// The router reacts to [AuthStatus.sessionExpired] by keeping the customer
  /// in guest-first browsing while account-only calls can prompt login again.
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
