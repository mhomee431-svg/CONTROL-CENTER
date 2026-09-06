import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_providers.dart';
import '../../data/phone_auth_service.dart';
import '../../data/phone_utils.dart';
import '../../domain/auth_models.dart';
import '../../data/auth_repository.dart';
import 'selected_shop.dart';

enum AuthStatus {
  initial,
  loading,
  otpSent,
  authenticated,
  unauthenticated,
  sessionExpired,
  error,
}

class AuthState {
  const AuthState({
    required this.status,
    this.errorMessage,
    this.phoneNumber,
    this.pendingName,
    this.user,
    this.shops = const [],
  });

  final AuthStatus status;
  final String? errorMessage;
  final String? phoneNumber;

  /// Set when the OTP flow was started as a REGISTRATION.
  final String? pendingName;
  final ShopkeeperUser? user;
  final List<ShopSummary> shops;

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isLoading => status == AuthStatus.loading;

  factory AuthState.initial() =>
      const AuthState(status: AuthStatus.initial);
  factory AuthState.loading({AuthState? from}) => AuthState(
        status: AuthStatus.loading,
        phoneNumber: from?.phoneNumber,
        pendingName: from?.pendingName,
      );
  factory AuthState.otpSent(String phone, {String? pendingName}) => AuthState(
        status: AuthStatus.otpSent,
        phoneNumber: phone,
        pendingName: pendingName,
      );
  factory AuthState.authenticated({
    required ShopkeeperUser user,
    required List<ShopSummary> shops,
  }) =>
      AuthState(
        status: AuthStatus.authenticated,
        user: user,
        shops: shops,
      );
  factory AuthState.unauthenticated() =>
      const AuthState(status: AuthStatus.unauthenticated);
  factory AuthState.sessionExpired() =>
      const AuthState(status: AuthStatus.sessionExpired);
  factory AuthState.error(String message) =>
      AuthState(status: AuthStatus.error, errorMessage: message);
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  String? _pendingPassword;

  @override
  AuthState build() {
    // Install the global 401 → sign-out hook (no-op in tests that never
    // touch the network stack).
    globalUnauthorizedHandler = forceSessionExpired;
    return AuthState.initial();
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  PhoneAuthService get _phoneAuth => ref.read(phoneAuthServiceProvider);

  /// Restores a persisted session on app startup.
  Future<bool> checkSession() async {
    state = AuthState.loading();
    try {
      final session = await _repo.restoreSession();
      if (session != null) {
        state = AuthState.authenticated(
            user: session.user, shops: session.shops);
        return true;
      }
      state = AuthState.unauthenticated();
      return false;
    } catch (_) {
      state = AuthState.error('Could not verify your session.');
      return false;
    }
  }

  /// Send OTP via Firebase Phone Auth (client-side). No backend call.
  /// The phone number is normalised to E.164 (+91…) first so users can type a
  /// bare 10-digit Indian number.
  Future<bool> sendOtp(String phoneNumber) async {
    final normalized = normalizeIndianPhone(phoneNumber);
    state = AuthState.loading(from: state);
    final completer = Completer<bool>();
    try {
      await _phoneAuth.sendOtp(
        phoneNumber: normalized,
        onCodeSent: (verificationId) {
          state = AuthState.otpSent(
            normalized,
            pendingName: state.pendingName,
          );
          if (!completer.isCompleted) completer.complete(true);
        },
        onError: (message) {
          state = AuthState.error(message);
          if (!completer.isCompleted) completer.complete(false);
        },
      );
    } catch (e) {
      state = AuthState.error('Could not send the code. Try again.');
      if (!completer.isCompleted) completer.complete(false);
    }
    return completer.future;
  }

  /// Firebase login-or-register: verifies OTP via Firebase, then calls the
  /// backend which auto-creates the account if the phone is new.
  Future<bool> loginWithFirebaseAuto({required String firebaseIdToken, String? name}) async {
    state = AuthState.loading(from: state);
    try {
      final session = await _repo.loginWithFirebaseAuto(
        firebaseIdToken: firebaseIdToken,
        name: name,
      );
      state = AuthState.authenticated(user: session.user, shops: session.shops);
      return true;
    } on ApiException catch (e) {
      state = AuthState.error(e.message);
      return false;
    } catch (_) {
      state = AuthState.error('Login failed. Please try again.');
      return false;
    }
  }

  /// Login with password (email/phone + password).
  Future<bool> loginWithPassword(String identifier, String password) async {
    state = AuthState.loading(from: state);
    try {
      final session = await _repo.loginWithPassword(
        identifier: identifier,
        password: password,
      );
      state = AuthState.authenticated(
          user: session.user, shops: session.shops);
      return true;
    } on ApiException catch (e) {
      state = AuthState.error(e.message);
      return false;
    } catch (_) {
      state = AuthState.error('Login failed. Please try again.');
      return false;
    }
  }

  /// Marks the running OTP flow as a REGISTRATION for [name] with [password].
  void beginRegistration(String phoneNumber, String name, [String? password]) {
    state = AuthState(
      status: state.status,
      errorMessage: state.errorMessage,
      phoneNumber: phoneNumber,
      pendingName: name,
      user: state.user,
      shops: state.shops,
    );
    _pendingPassword = password;
  }

  /// Verify the SMS code via Firebase, then register/login on the backend
  /// using the resulting Firebase ID token.
  Future<bool> submitOtp({
    required String phoneNumber,
    required String otp,
  }) async {
    state = AuthState.loading(from: state);
    try {
      // 1) Verify the OTP with Firebase → get ID token.
      final result = await _phoneAuth.verifyOtp(smsCode: otp);

      // 2) Use the token to register or log in on the backend.
      final name = state.pendingName;
      final session = (name != null && name.isNotEmpty)
          ? await _repo.registerWithFirebase(
              phoneNumber: result.phoneNumber,
              firebaseIdToken: result.idToken,
              name: name,
              password: _pendingPassword,
            )
          : await _repo.loginWithFirebase(
              firebaseIdToken: result.idToken,
            );
      state = AuthState.authenticated(
          user: session.user, shops: session.shops);
      return true;
    } on ApiException catch (e) {
      state = AuthState.error(e.message);
      return false;
    } on PhoneAuthException catch (e) {
      state = AuthState.error(e.message);
      return false;
    } catch (_) {
      state = AuthState.error('Verification failed. Please retry.');
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await _repo.logout();
    } catch (_) {
      // Local sign-out must always complete.
    }
    ref.read(selectedShopProvider.notifier).select(null);
    state = AuthState.unauthenticated();
  }

  /// Request password reset.
  Future<void> forgotPassword(String identifier) async {
    state = AuthState.loading(from: state);
    try {
      await _repo.forgotPassword(identifier);
      state = AuthState.unauthenticated();
    } on ApiException catch (e) {
      state = AuthState.error(e.message);
      rethrow;
    } catch (_) {
      state = AuthState.error('Failed to send reset link');
      rethrow;
    }
  }

  /// Reset password with token.
  Future<void> resetPassword({required String token, required String newPassword}) async {
    state = AuthState.loading(from: state);
    try {
      await _repo.resetPassword(token: token, newPassword: newPassword);
      state = AuthState.unauthenticated();
    } on ApiException catch (e) {
      state = AuthState.error(e.message);
      rethrow;
    } catch (_) {
      state = AuthState.error('Failed to reset password');
      rethrow;
    }
  }

  /// Called by the API layer when a session becomes unrecoverable (401).
  void forceSessionExpired() {
    if (state.status == AuthStatus.unauthenticated) return;
    state = AuthState.sessionExpired();
  }
}
