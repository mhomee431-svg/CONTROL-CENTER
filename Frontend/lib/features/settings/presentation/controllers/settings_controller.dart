import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_strings.dart';
import '../../../../core/storage/local_storage_driver.dart';
import '../../domain/models/app_settings.dart';

final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

final appStringsProvider = Provider<AppStrings>((ref) {
  final settings = ref.watch(settingsControllerProvider);
  return AppStrings(settings.languageCode);
});

/// Local storage key for the serialized settings document.
const String appSettingsStorageKey = 'app_settings_v1';

/// Device/app-level settings with local persistence.
///
/// State is available synchronously (defaults) and hydrated from
/// [LocalStorageDriver] right after build; every mutation writes through
/// so choices survive restarts.
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    // Hydrate asynchronously without blocking first frame.
    Future.microtask(_hydrate);
    return const AppSettings();
  }

  Future<void> _hydrate() async {
    try {
      final raw = await ref.read(localStorageDriverProvider).getString(
            appSettingsStorageKey,
          );
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        state = AppSettings.fromJson(decoded);
      }
    } catch (_) {
      // Corrupt payload — keep defaults.
    }
  }

  Future<void> _persist() async {
    try {
      await ref.read(localStorageDriverProvider).setString(
            appSettingsStorageKey,
            jsonEncode(state.toJson()),
          );
    } catch (_) {
      // Persistence is best-effort; in-memory state remains authoritative.
    }
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    unawaitedPersist();
  }

  void setLanguage(String code) {
    state = state.copyWith(languageCode: code);
    unawaitedPersist();
  }

  /// Master push switch for this device. Toggling also drives the
  /// device-token registration flow via the auth listener in app.dart.
  void toggleNotifications(bool val) {
    state = state.copyWith(pushNotificationsEnabled: val);
    unawaitedPersist();
  }

  void toggleLocation(bool val) {
    state = state.copyWith(locationEnabled: val);
    unawaitedPersist();
  }

  void setAnalytics(bool val) {
    state = state.copyWith(analyticsEnabled: val);
    unawaitedPersist();
  }

  void setCrashReporting(bool val) {
    state = state.copyWith(crashReportingEnabled: val);
    unawaitedPersist();
  }

  void setPersonalizedRecommendations(bool val) {
    state = state.copyWith(personalizedRecommendations: val);
    unawaitedPersist();
  }

  // Small alias to keep call sites terse.
  void unawaitedPersist() => _persist();
}
