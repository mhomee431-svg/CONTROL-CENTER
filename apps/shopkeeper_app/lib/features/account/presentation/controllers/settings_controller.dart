import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/controllers/auth_controller.dart';

/// Languages the shopkeeper app can display.
///
/// Only [english] is shipped in this release. The enum is the app's real
/// vocabulary for the choice (instead of a bare string that would drift), so
/// adding a language later is one entry here plus the message bundle — the
/// Language screen and its persistence need no changes.
enum AppLanguage {
  english('English', 'en'),
  hindi('हिन्दी', 'hi', isAvailable: false),
  tamil('தமிழ்', 'ta', isAvailable: false),
  bengali('বাংলা', 'bn', isAvailable: false);

  const AppLanguage(this.label, this.code, {this.isAvailable = true});

  /// Name shown in the language list, in the language's own script.
  final String label;

  /// BCP-47 language subtag.
  final String code;

  /// `false` while the UI strings for this language are not bundled yet. Such a
  /// row is listed so the shopkeeper can see what is planned, but it cannot be
  /// selected — a picker that silently keeps showing English would be a lie.
  final bool isAvailable;

  /// Locales the app ships translations for, fed to `MaterialApp`.
  ///
  /// Deliberately only the *available* languages: a locale the app cannot
  /// render must fall back to English through Flutter's locale resolution, not
  /// be promised as supported.
  static List<Locale> get supportedLocales => [
        for (final language in values)
          if (language.isAvailable) Locale(language.code),
      ];

  /// Language matching a stored/BCP-47 code, falling back to [english].
  static AppLanguage fromCode(String? code) {
    if (code == null) return english;
    final base = code.split(RegExp(r'[-_]')).first.toLowerCase();
    for (final language in values) {
      if (language.code == base) return language;
    }
    return english;
  }
}

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

  /// Switches the app language.
  ///
  /// Only [AppLanguage.isAvailable] languages are accepted: an unavailable row
  /// on the Language screen is informational, so a stray call can never put the
  /// app into a language whose strings are not bundled.
  void setLanguage(AppLanguage language) {
    if (!language.isAvailable) return;
    if (language == state.language) return;
    state = state.copyWith(language: language);
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
    this.language = AppLanguage.english,
    this.loggingOut = false,
  });

  /// Device-level theme choice. NOT reset on logout: it is a display
  /// preference, not account data.
  final ThemeMode themeMode;

  /// Display language. Like [themeMode] it is a display preference, so signing
  /// out leaves it alone.
  final AppLanguage language;

  /// True while [SettingsController.logout] runs — the confirmation screen
  /// shows a progress indicator instead of a dead button.
  final bool loggingOut;

  SettingsState copyWith({
    ThemeMode? themeMode,
    AppLanguage? language,
    bool? loggingOut,
  }) =>
      SettingsState(
        themeMode: themeMode ?? this.themeMode,
        language: language ?? this.language,
        loggingOut: loggingOut ?? this.loggingOut,
      );
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsState>(SettingsController.new);