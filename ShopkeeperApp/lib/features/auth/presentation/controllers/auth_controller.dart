import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/env_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_providers.dart';
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
    this.isGuest = false, // TEMP/DEV: hardcoded-login; remove with that feature.
  });

  final AuthStatus status;
  final String? errorMessage;
  final String? phoneNumber;

  /// Set when the OTP flow was started as a REGISTRATION.
  final String? pendingName;
  final ShopkeeperUser? user;
  final List<ShopSummary> shops;

  /// TEMP/DEV ONLY — true when the session was created by the hardcoded
  /// ID/password login instead of a real backend OTP login. Guest sessions
  /// must never be hard-logged-out on 401 responses.
  final bool isGuest;

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

  Future<bool> sendOtp(String phoneNumber) async {
    state = AuthState.loading(from: state);
    try {
      await _repo.sendOtp(phoneNumber);
      state = AuthState.otpSent(
        phoneNumber,
        pendingName: state.pendingName,
      );
      return true;
    } on ApiException catch (e) {
      state = AuthState.error(e.message);
      return false;
    } catch (_) {
      state = AuthState.error('Could not send the code. Try again.');
      return false;
    }
  }

  /// Marks the running OTP flow as a REGISTRATION for [name].
  void beginRegistration(String phoneNumber, String name) {
    state = AuthState(
      status: state.status,
      errorMessage: state.errorMessage,
      phoneNumber: phoneNumber,
      pendingName: name,
      user: state.user,
      shops: state.shops,
    );
  }

  Future<bool> submitOtp({
    required String phoneNumber,
    required String otp,
  }) async {
    state = AuthState.loading(from: state);
    try {
      final name = state.pendingName;
      final session = (name != null && name.isNotEmpty)
          ? await _repo.register(
              phoneNumber: phoneNumber, otp: otp, name: name)
          : await _repo.login(phoneNumber: phoneNumber, otp: otp);
      state = AuthState.authenticated(
          user: session.user, shops: session.shops);
      return true;
    } on ApiException catch (e) {
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

  // ────────────────────────────────────────────────────────────────────────
  // TEMP/DEV HARDCODED LOGIN — remove before release.
  //
  // Opens a local demo session (demo user + demo shop) WITHOUT calling the
  // backend, when the entered ID/password match the hardcoded values in
  // [EnvConfig]. The real OTP flow (sendOtp → submitOtp) is untouched and
  // keeps working normally alongside this.
  //
  // To restore original behaviour later:
  //   1. Delete [loginWithCredentials] and [skipLogin] below.
  //   2. Remove the Password field + credential branch in login_screen.dart.
  //   3. Restore forceSessionExpired to: unauthenticated-guard only
  //      (original lines are commented inside it).
  //   4. Remove `isGuest` from AuthState and the constants from EnvConfig.
  // ────────────────────────────────────────────────────────────────────────

  /// Validates the entered credentials against the hardcoded demo values.
  /// Returns true (and opens a demo session) on success.
  Future<bool> loginWithCredentials(String id, String password) async {
    final ok = id.trim() == EnvConfig.demoLoginId &&
        password == EnvConfig.demoLoginPassword;
    if (!ok) {
      state = const AuthState(
          status: AuthStatus.error,
          errorMessage: 'Invalid ID or password.');
      return false;
    }
    skipLogin();
    return true;
  }

  /// Creates the local demo session used by the hardcoded login.
  void skipLogin() {
    const demoUser = ShopkeeperUser(
      id: -1,
      phoneNumber: '+919999999999',
      name: 'Demo Shopkeeper',
      email: null,
      role: 'owner',
    );
    const demoShop = ShopSummary(
      id: -1,
      name: 'Demo Shop',
      status: 'REGISTERED',
      isVerified: true,
      category: 'Grocery',
      imageUrl: null,
      membership: 'owner',
      permissions: ['update:shop', 'create:product', 'update:product'],
    );

    // Pre-select the demo shop so the router guard goes straight to
    // /dashboard instead of bouncing to /shops or /shop-register.
    ref.read(selectedShopProvider.notifier).select(demoShop);
    state = const AuthState(
      status: AuthStatus.authenticated,
      user: demoUser,
      shops: [demoShop],
      isGuest: true,
    );
  }

  /// Called by the API layer when a session becomes unrecoverable (401).
  void forceSessionExpired() {
    if (state.status == AuthStatus.unauthenticated) return;
    // TEMP/DEV: hardcoded-login sessions have no server-side session to
    // expire — keep the user inside so they can keep exploring the UI.
    if (state.isGuest) return; // TEMP/DEV line — remove with the feature.
    state = AuthState.sessionExpired();
  }
}
