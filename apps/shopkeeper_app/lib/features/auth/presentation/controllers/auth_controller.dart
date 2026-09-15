import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_providers.dart';
import '../../../../core/network/token_store.dart';
import '../../../../core/auth/firebase_auth_service.dart';
import '../../domain/auth_models.dart';
import '../../data/auth_repository.dart';
import '../../../dashboard/presentation/controllers/dashboard_controller.dart';
import '../../../products/presentation/controllers/products_controller.dart';
import '../../../shops/presentation/controllers/shops_controller.dart';
import '../../../notifications/presentation/controllers/notifications_controller.dart';
import '../../../barcode/presentation/controllers/barcode_controller.dart';
import '../../../inventory_import/presentation/controllers/import_controller.dart';
import '../../../insights/presentation/controllers/insights_controller.dart';
import 'selected_shop.dart';

enum AuthStatus {
  initial,
  loading,
  authenticated,
  unauthenticated,
  sessionExpired,
  error,

  /// Backend reports the account INACTIVE / SUSPENDED / BANNED — routed to
  /// the account-status screen instead of the normal app (Phase 23).
  accountRestricted,
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

  /// Single-shop model: a profile is "complete" once the shopkeeper has
  /// registered their first (and only) shop. Incomplete → create-profile
  /// screen; complete → dashboard.
  bool get profileComplete => shops.isNotEmpty;

  factory AuthState.initial() => const AuthState(status: AuthStatus.initial);
  factory AuthState.loading() => const AuthState(status: AuthStatus.loading);
  factory AuthState.authenticated({
    required ShopkeeperUser user,
    required List<ShopSummary> shops,
  }) => AuthState(status: AuthStatus.authenticated, user: user, shops: shops);
  factory AuthState.unauthenticated() =>
      const AuthState(status: AuthStatus.unauthenticated);
  factory AuthState.sessionExpired() =>
      const AuthState(status: AuthStatus.sessionExpired);

  /// Account inactive/suspended — the message comes from the backend
  /// (or the startup status check) and is shown on the account-status screen.
  factory AuthState.accountRestricted(String message, {String? errorCode}) =>
      AuthState(
        status: AuthStatus.accountRestricted,
        errorMessage: message,
        errorCode: errorCode,
      );
  factory AuthState.error(String message, {String? errorCode}) => AuthState(
    status: AuthStatus.error,
    errorMessage: message,
    errorCode: errorCode,
  );
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    // Install the global 401 → sign-out hook (no-op in tests that never
    // touch the network stack).
    globalUnauthorizedHandler = forceSessionExpired;

    // SINGLE SOURCE OF TRUTH (authorized businesses): ShopsController is the
    // ONLY place that fetches the shop list from the backend
    // (`GET /shopkeeper/shops`). Whenever it publishes a fresh `ready` list,
    // this listener mirrors it into the session snapshot ([AuthState.shops])
    // that the router guards and [selectBusiness] read, and runs the ONE
    // selection policy ([_syncPrimaryShop]). No second copy of the list can
    // drift — registration, refresh and sign-in all converge here.
    ref.listen<ShopsState>(shopsControllerProvider, (prev, next) {
      if (next.status == ShopsStatus.ready) {
        _syncAuthorizedShops(next.shops);
      }
    });

    return AuthState.initial();
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  /// Single-shop model: auto-selects the shop returned by the backend so the
  /// whole app is scoped to ONE business. If the account has no shop yet,
  /// clears the selection (dashboard shows the onboarding CTA).
  ///
  /// Extensibility note: only the FIRST shop is treated as primary today; the
  /// list stays in the model so multi-shop can be enabled later without a
  /// rewrite.
  void _syncPrimaryShop(List<ShopSummary> shops) {
    if (shops.isNotEmpty) {
      final current = ref.read(selectedShopProvider);
      if (current == null || !shops.any((s) => s.id == current.id)) {
        ref.read(selectedShopProvider.notifier).select(shops.first);
      }
    } else {
      ref.read(selectedShopProvider.notifier).select(null);
    }
  }

  /// Mirrors a freshly-fetched authorized-shops list into the session
  /// snapshot and re-runs the single selection policy. Called by the
  /// [shopsControllerProvider] listener in [build] — the only path through
  /// which [AuthState.shops] changes after sign-in.
  void _syncAuthorizedShops(List<ShopSummary> shops) {
    final current = state;
    if (!current.isAuthenticated) return;
    if (listEquals(current.shops, shops)) return;
    state = AuthState.authenticated(
      user: current.user ??
          const ShopkeeperUser(
            id: 0,
            phoneNumber: '',
            name: '',
            role: 'shopkeeper',
          ),
      shops: shops,
    );
    _syncPrimaryShop(shops);
  }

  /// Called after the user completes first-time profile creation. Adds the
  /// new shop to the auth state so `profileComplete` becomes true and the
  /// router lands on the Dashboard.
  Future<void> refreshAfterProfileCreate(ShopSummary shop) async {
    final current = state;
    final updatedShops = [shop];
    ref.read(selectedShopProvider.notifier).select(shop);
    state = AuthState.authenticated(
      user:
          current.user ??
          const ShopkeeperUser(
            id: 0,
            phoneNumber: '',
            name: '',
            role: 'shopkeeper',
          ),
      shops: updatedShops,
    );
  }

  /// Restores a persisted session on app startup (Phase 23):
  ///
  ///   1. Stored backend session still valid (`/me`) → authenticated.
  ///   2. Otherwise check the DEVICE Firebase auth state:
  ///        • No Firebase user → wipe stale app tokens → unauthenticated
  ///          (the router sends the user to login).
  ///        • Firebase user present → fresh Firebase ID token → backend
  ///          current-profile verification (`/firebase-login`, Admin-SDK
  ///          verified) → authenticated.
  ///   3. Backend reports the account INACTIVE/SUSPENDED/BANNED →
  ///      account-restricted state (routed to the account-status screen).
  Future<bool> checkSession() async {
    state = AuthState.loading();
    try {
      // ── 1. Fast path: the stored backend JWT is still valid. ──
      final session = await _repo.restoreSession();
      if (session != null) {
        final restriction = _accountRestriction(session.user.status);
        if (restriction != null) {
          state = AuthState.accountRestricted(
            restriction.message,
            errorCode: restriction.code,
          );
          return false;
        }
        _syncPrimaryShop(session.shops);
        state = AuthState.authenticated(
          user: session.user,
          shops: session.shops,
        );
        return true;
      }

      // ── 2. Check the device Firebase auth state. ──
      final firebaseUser = ref.read(firebaseAuthServiceProvider).currentUser;
      if (firebaseUser == null) {
        // Unauthenticated at the Firebase level → clear any stale app-side
        // tokens so NO authenticated state stays cached, then land on login.
        await ref.read(tokenStoreProvider).clearAll();
        state = AuthState.unauthenticated();
        return false;
      }

      // ── 3. Firebase user present → fresh ID token → backend profile. ──
      final String? idToken = await firebaseUser.getIdToken(true);
      if (idToken == null || idToken.isEmpty) {
        // Firebase present but no usable token → wipe stale app tokens and
        // land on login (matches the signed-out device path).
        await ref.read(tokenStoreProvider).clearAll();
        state = AuthState.unauthenticated();
        return false;
      }
      final fresh = await _repo.firebaseLogin(
        firebaseIdToken: idToken,
        name: firebaseUser.displayName,
        email: firebaseUser.email,
        photoUrl: firebaseUser.photoURL,
      );
      final freshRestriction = _accountRestriction(fresh.user.status);
      if (freshRestriction != null) {
        state = AuthState.accountRestricted(
          freshRestriction.message,
          errorCode: freshRestriction.code,
        );
        return false;
      }
      _syncPrimaryShop(fresh.shops);
      state = AuthState.authenticated(user: fresh.user, shops: fresh.shops);
      return true;
    } on ApiException catch (e) {
      // Backend refused the account (Phase 23) → account-status screen.
      if (e.errorCode == 'ACCOUNT_NOT_ACTIVE') {
        state = AuthState.accountRestricted(
          e.message.isNotEmpty ? e.message : 'Account is not active.',
          errorCode: e.errorCode,
        );
        return false;
      }
      // Expired/invalid stored token (already wiped by the repository) or a
      // transient backend failure → normal signed-out landing.
      state = AuthState.unauthenticated();
      return false;
    } catch (_) {
      state = AuthState.unauthenticated();
      return false;
    }
  }

  /// Maps a backend account lifecycle status to the account-status screen
  /// copy. Returns null for active/unknown statuses (normal app).
  ({String code, String message})? _accountRestriction(String? status) {
    return switch (status?.toUpperCase()) {
      'SUSPENDED' => (
        code: 'ACCOUNT_NOT_ACTIVE',
        message: 'Your account has been suspended. Please contact support.',
      ),
      'BANNED' => (
        code: 'ACCOUNT_NOT_ACTIVE',
        message: 'Your account has been banned. Please contact support.',
      ),
      'INACTIVE' => (
        code: 'ACCOUNT_NOT_ACTIVE',
        message: 'Your account is inactive. Please contact support to reactivate it.',
      ),
      _ => null,
    };
  }

  /// FUTURE (Phone OTP) — function seam, UI intentionally absent in the MVP.
  ///
  /// Completes sign-in from a Firebase Phone-Auth ID token. The future OTP UI
  /// is responsible for obtaining the token (`signInWithPhoneNumber` →
  /// confirmation → `getIdToken()`); this method applies the EXACT same
  /// session contract as [signInWithGoogle]: backend exchange → restriction
  /// gate → primary-shop sync → authenticated state. Because both providers
  /// yield the same Firebase ID-token shape, adding the OTP UI later requires
  /// no changes to this controller, the repository, or the session models.
  Future<bool> loginWithPhoneOtp({required String firebaseIdToken}) async {
    state = AuthState.loading();
    try {
      final session = await _repo.loginWithPhoneOtp(
        firebaseIdToken: firebaseIdToken,
      );
      final restriction = _accountRestriction(session.user.status);
      if (restriction != null) {
        state = AuthState.accountRestricted(
          restriction.message,
          errorCode: restriction.code,
        );
        return false;
      }
      _syncPrimaryShop(session.shops);
      state = AuthState.authenticated(user: session.user, shops: session.shops);
      return true;
    } on ApiException catch (e) {
      if (e.errorCode == 'ACCOUNT_NOT_ACTIVE') {
        state = AuthState.accountRestricted(
          e.message.isNotEmpty ? e.message : 'Account is not active.',
          errorCode: e.errorCode,
        );
        return false;
      }
      state = AuthState.error(e.message, errorCode: e.errorCode);
      return false;
    } catch (_) {
      state = AuthState.error('Sign-in failed. Please try again.');
      return false;
    }
  }

  /// Switches the business the app is scoped to.
  ///
  /// Single-shop MVP: the one authorized shop is auto-selected at sign-in
  /// ([_syncPrimaryShop]), so this is effectively a no-op today — but it is
  /// the CANONICAL entry point for future business switching / multi-business
  /// dashboards, so screens should call this instead of writing to
  /// [selectedShopProvider] directly.
  ///
  /// Authorization boundary: the shop MUST be one the backend granted access
  /// to ([AuthState.shops]). Unknown shops are rejected — the client never
  /// self-authorizes a business switch.
  bool selectBusiness(ShopSummary shop) {
    final authorized =
        state.shops.any((s) => s.id == shop.id);
    if (!authorized) return false;
    ref.read(selectedShopProvider.notifier).select(shop);
    return true;
  }

  /// Google Sign-In (Firebase Authentication).
  ///
  /// Flow: Google Sign-In → Firebase → Firebase ID token → backend
  /// ``/firebase-login`` (verified via Firebase Admin SDK) → session.
  ///
  /// The Firebase back-end is platform-specific: native Credential Manager on
  /// Android, Firebase JS popup on web — both yield the same ID token.
  Future<bool> signInWithGoogle() async {
    debugPrint('╔══════════════════════════════════════════════════════════');
    debugPrint('║  GOOGLE SIGN-IN FLOW STARTED');
    debugPrint('╚══════════════════════════════════════════════════════════');
    state = AuthState.loading();
    try {
      // ── STEP 1: Firebase Google Sign-In ────────────────────────────
      debugPrint('STEP 1: Calling FirebaseAuthService.signInWithGoogle()...');
      final result = await ref
          .read(firebaseAuthServiceProvider)
          .signInWithGoogle();
      final firebaseUser = result.user;
      debugPrint('STEP 1 ✓: Firebase user obtained');
      debugPrint('  ├─ UID: ${firebaseUser.uid}');
      debugPrint('  ├─ Display Name: ${firebaseUser.displayName}');
      debugPrint('  ├─ Email: ${firebaseUser.email}');
      debugPrint('  ├─ Photo URL: ${firebaseUser.photoURL}');
      debugPrint(
        '  ├─ ID Token (first 30 chars): ${result.idToken.length > 30 ? result.idToken.substring(0, 30) : result.idToken}...',
      );
      debugPrint('  └─ ID Token length: ${result.idToken.length} chars');

      // ── STEP 2: Backend API Call ───────────────────────────────────
      debugPrint('STEP 2: Sending ID token to backend /firebase-login...');
      final session = await _repo.firebaseLogin(
        firebaseIdToken: result.idToken,
        name: firebaseUser.displayName,
        email: firebaseUser.email,
        photoUrl: firebaseUser.photoURL,
      );
      debugPrint('STEP 2 ✓: Backend responded with session');
      debugPrint('  ├─ User ID: ${session.user.id}');
      debugPrint('  ├─ User Name: ${session.user.name}');
      debugPrint('  ├─ Business ID: ${session.user.businessId}');
      debugPrint('  └─ Shops count: ${session.shops.length}');

      // ── STEP 3: Update Auth State ──────────────────────────────────
      debugPrint('STEP 3: Updating auth state to AUTHENTICATED...');
      _syncPrimaryShop(session.shops);
      state = AuthState.authenticated(user: session.user, shops: session.shops);
      debugPrint('STEP 3 ✓: Auth state is now AUTHENTICATED');

      // ── STEP 4: Verify Token Saved ─────────────────────────────────
      debugPrint('STEP 4: Verifying local storage...');
      final savedToken = await _repo.debugReadToken();
      final savedUserId = await _repo.debugReadUserId();
      final isLoggedIn = await _repo.debugIsLoggedIn();
      debugPrint('STEP 4 ✓: Local storage status:');
      debugPrint(
        '  ├─ jwt_token saved: ${savedToken != null && savedToken.isNotEmpty}',
      );
      debugPrint('  ├─ user_id saved: ${savedUserId ?? "null"}');
      debugPrint('  └─ is_logged_in: $isLoggedIn');

      debugPrint('╔══════════════════════════════════════════════════════════');
      debugPrint('║  GOOGLE SIGN-IN FLOW COMPLETED SUCCESSFULLY ✓');
      debugPrint('╚══════════════════════════════════════════════════════════');
      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint('✗ FirebaseAuthException caught:');
      debugPrint('  ├─ Code: ${e.code}');
      debugPrint('  ├─ Message: ${e.message}');
      debugPrint('  └─ Credential: ${e.credential}');
      // Closing the picker/popup/browser sheet is a normal cancel, not an
      // error. `canceled` / `web-context-cancelled` are what the iOS OAuth
      // provider flow returns when the user dismisses Safari.
      if (e.code == 'google-sign-in-cancelled' ||
          e.code == 'auth/popup-closed-by-user' ||
          e.code == 'canceled' ||
          e.code == 'web-context-cancelled') {
        debugPrint('→ User cancelled sign-in (not an error)');
        state = AuthState.unauthenticated();
      } else {
        state = AuthState.error(
          e.message ?? 'Google sign-in failed.',
          errorCode: e.code,
        );
      }
      return false;
    } on ApiException catch (e) {
      debugPrint('✗ ApiException caught (backend error):');
      debugPrint('  ├─ Status Code: ${e.statusCode}');
      debugPrint('  ├─ Error Code: ${e.errorCode}');
      debugPrint('  └─ Message: ${e.message}');
      state = AuthState.error(e.message, errorCode: e.errorCode);
      return false;
    } catch (e, stackTrace) {
      debugPrint('✗ Unexpected error caught:');
      debugPrint('  ├─ Error: $e');
      debugPrint('  └─ Stack trace: $stackTrace');
      state = AuthState.error('Google sign-in failed. Please try again.');
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
      _syncPrimaryShop(session.shops);
      state = AuthState.authenticated(user: session.user, shops: session.shops);
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
      _syncPrimaryShop(session.shops);
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

  /// Completes the shopkeeper profile after social sign-in (name + phone).
  ///
  /// Calls the backend profile endpoint (name/email — phone is accepted for
  /// contract compatibility) and refreshes the session.
  Future<bool> createProfile({
    required String name,
    String? phoneNumber,
  }) async {
    state = AuthState.loading();
    try {
      final session = await _repo.updateProfile(
        name: name,
        phoneNumber: phoneNumber,
      );
      _syncPrimaryShop(session.shops);
      state = AuthState.authenticated(user: session.user, shops: session.shops);
      return true;
    } on ApiException catch (e) {
      state = AuthState.error(e.message, errorCode: e.errorCode);
      return false;
    } catch (_) {
      state = AuthState.error('Could not save your profile. Please retry.');
      return false;
    }
  }

  /// Full sign-out flow (Phase 22):
  ///
  ///   Firebase signOut()  →  backend session revoke + secure-store wipe
  ///   →  clear every cached authenticated state (selected shop, shops list,
  ///   dashboard data, inventory)  →  unauthenticated (router lands on login).
  ///
  /// Network/Firebase steps are best-effort: a dead connection or an
  /// un-initialised Firebase core must never leave the user stuck in an
  /// authenticated UI. The local state reset ALWAYS completes, so no
  /// authenticated application state is cached after logout.
  Future<void> logout() async {
    // 1) Sign out of Firebase — clears the Google/Firebase session and any
    //    cached credentials on the device.
    try {
      await ref.read(firebaseAuthServiceProvider).signOut();
    } catch (_) {
      // Best-effort: tests (no Firebase app) and desktop/web must still be
      // able to sign out. The next native sign-in also clears stale sessions.
    }

    // 2) Revoke the backend session and wipe every stored token.
    try {
      await _repo.logout();
    } catch (_) {
      // Server revocation failures must not block local sign-out.
    }

    // 3) Drop ALL cached authenticated application state — nothing from the
    //    previous account may survive into the next session.
    ref.read(selectedShopProvider.notifier).select(null);
    ref.read(shopsControllerProvider.notifier).reset();
    ref.read(dashboardControllerProvider.notifier).reset();
    ref.read(productsControllerProvider.notifier).reset();
    ref.read(notificationsControllerProvider.notifier).reset();
    ref.read(barcodeControllerProvider.notifier).reset();
    ref.read(importControllerProvider.notifier).reset();
    // Customer-activity reports are scoped to one account's shops — they must
    // never survive into the next session.
    ref.read(insightsControllerProvider.notifier).reset();

    // 4) Unauthenticated → the router redirect sends the user to login.
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
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
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
