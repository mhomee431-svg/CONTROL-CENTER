import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_providers.dart';
import '../../domain/auth_models.dart';
import '../../data/auth_repository.dart';
import 'selected_shop.dart';

enum AuthStatus {
  initial,
  loading,
  authenticated,
  unauthenticated,
  sessionExpired,
  error,
}

class AuthState {
  const AuthState({
    required this.status,
    this.errorMessage,
    this.errorCode,
    this.user,
    this.shops = const [],
  });

  final AuthStatus status;
  final String? errorMessage;
  final String? errorCode;
  final ShopkeeperUser? user;
  final List<ShopSummary> shops;

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isLoading => status == AuthStatus.loading;

  factory AuthState.initial() =>
      const AuthState(status: AuthStatus.initial);
  factory AuthState.loading() =>
      const AuthState(status: AuthStatus.loading);
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
  factory AuthState.error(String message, {String? errorCode}) =>
      AuthState(status: AuthStatus.error, errorMessage: message, errorCode: errorCode);
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    // Install the global 401 → sign-out hook (no-op in tests that never
    // touch the network stack).
    globalUnauthorizedHandler = forceSessionExpired;
    return AuthState.initial();
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

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

  /// Simple registration: phone + password.
  Future<bool> registerWithPassword({
    required String name,
    required String phoneNumber,
    required String password,
  }) async {
    state = AuthState.loading();
    try {
      final session = await _repo.registerWithPassword(
        name: name,
        phoneNumber: phoneNumber,
        password: password,
      );
      state = AuthState.authenticated(
          user: session.user, shops: session.shops);
      return true;
    } on ApiException catch (e) {
      state = AuthState.error(e.message, errorCode: e.errorCode);
      return false;
    } catch (_) {
      state = AuthState.error('Registration failed. Please retry.');
      return false;
    }
  }

  /// Login with password (email/phone + password).
  Future<bool> loginWithPassword(String identifier, String password) async {
    state = AuthState.loading();
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
    state = AuthState.loading();
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
    state = AuthState.loading();
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