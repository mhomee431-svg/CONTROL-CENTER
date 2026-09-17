import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/controllers/auth_controller.dart';

/// Central account/settings controller.
///
/// Owns exactly two things, both of which are pure app-side concerns:
///
///  * **Theme preference** — the one setting the app can honour without a
///    backend round-trip. `ShopkeeperApp` watches this provider, so picking
///    Light/Dark/System in *App settings* re-themes the whole app instantly.
///  * **Sign-out sequencing** — [logout] owns the UI side of logging out (the
///    in-flight flag used to disable buttons) and DELEGATES the teardown to
///    `AuthController.logout()`, the single source of truth that revokes the
///    backend session, wipes the token store and resets every cached
///    controller. Re-implementing that sequence here is exactly how the first
///    draft ended up calling a `reset()` that does not exist.
class SettingsController extends Notifier<SettingsState> {
  @override
  SettingsState build() => const SettingsState();

  /// Rethemes the app immediately (see `ShopkeeperApp.themeMode`).
  void setThemeMode(ThemeMode mode) {
    if (mode == state.themeMode) return;
    state = state.copyWith(themeMode: mode);
  }

  /// Signs the shopkeeper out after they confirm it on
  /// `LogoutConfirmationScreen`.
  ///
  /// Returns normally even when the backend revoke or the Firebase sign-out
  /// fails: `AuthController.logout()` treats those steps as best-effort and
  /// ALWAYS clears the local session, so the router lands on Welcome either way.
  Future<void> logout() async {
    if (state.loggingOut) return;
    state = state.copyWith(loggingOut: true);
    try {
      await ref.read(authControllerProvider.notifier).logout();
    } finally {
      // The screen may already be unmounted (the router redirects to Welcome
      // the moment auth state flips) — only touch state while it is still ours.
      if (state.loggingOut) state = state.copyWith(loggingOut: false);
    }
  }
}

/// Immutable settings surface.
class SettingsState {
  const SettingsState({
    this.themeMode = ThemeMode.system,
    this.loggingOut = false,
  });

  /// Device-level theme choice. NOT reset on logout: it is a display
  /// preference, not account data.
  final ThemeMode themeMode;

  /// True while [SettingsController.logout] runs — the confirmation screen
  /// shows a progress indicator instead of a dead button.
  final bool loggingOut;

  SettingsState copyWith({ThemeMode? themeMode, bool? loggingOut}) =>
      SettingsState(
        themeMode: themeMode ?? this.themeMode,
        loggingOut: loggingOut ?? this.loggingOut,
      );
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsState>(SettingsController.new);