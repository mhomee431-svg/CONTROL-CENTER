import 'package:flutter/material.dart';

/// Device/app-level settings the customer controls.
///
/// Notification *account* preferences (per-type, per-channel) live in
/// [NotificationPreferences]; everything here is local device state,
/// persisted as JSON through [LocalStorageDriver].
class AppSettings {
  final ThemeMode themeMode;
  final String languageCode; // 'en' or 'hi'

  // ── Location preferences ──────────────────────────────────────────
  /// Master switch for GPS/location usage by discovery features.
  final bool locationEnabled;

  // ── Notification (device-level) ───────────────────────────────────
  /// Whether this device accepts push notifications at all. When off,
  /// the device token is unregistered from the future backend service.
  final bool pushNotificationsEnabled;

  // ── Privacy-related settings ──────────────────────────────────────
  /// Anonymous usage analytics. Privacy-first default: OFF until the
  /// customer opts in.
  final bool analyticsEnabled;

  /// Crash reporting to help diagnose failures.
  final bool crashReportingEnabled;

  /// Personalised recommendations based on viewed/saved items.
  final bool personalizedRecommendations;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.languageCode = 'en',
    this.locationEnabled = true,
    this.pushNotificationsEnabled = true,
    this.analyticsEnabled = false,
    this.crashReportingEnabled = true,
    this.personalizedRecommendations = true,
  });

  static const String _themeKey = 'themeMode';
  static const String _languageKey = 'languageCode';
  static const String _locationKey = 'locationEnabled';
  static const String _pushKey = 'pushNotificationsEnabled';
  static const String _analyticsKey = 'analyticsEnabled';
  static const String _crashKey = 'crashReportingEnabled';
  static const String _personalizationKey = 'personalizedRecommendations';

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? languageCode,
    bool? locationEnabled,
    bool? pushNotificationsEnabled,
    bool? analyticsEnabled,
    bool? crashReportingEnabled,
    bool? personalizedRecommendations,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      languageCode: languageCode ?? this.languageCode,
      locationEnabled: locationEnabled ?? this.locationEnabled,
      pushNotificationsEnabled:
          pushNotificationsEnabled ?? this.pushNotificationsEnabled,
      analyticsEnabled: analyticsEnabled ?? this.analyticsEnabled,
      crashReportingEnabled: crashReportingEnabled ?? this.crashReportingEnabled,
      personalizedRecommendations:
          personalizedRecommendations ?? this.personalizedRecommendations,
    );
  }

  Map<String, dynamic> toJson() => {
        _themeKey: themeMode.name,
        _languageKey: languageCode,
        _locationKey: locationEnabled,
        _pushKey: pushNotificationsEnabled,
        _analyticsKey: analyticsEnabled,
        _crashKey: crashReportingEnabled,
        _personalizationKey: personalizedRecommendations,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere(
        (mode) => mode.name == json[_themeKey],
        orElse: () => ThemeMode.system,
      ),
      languageCode: json[_languageKey] == 'hi' ? 'hi' : 'en',
      locationEnabled: json[_locationKey] as bool? ?? true,
      pushNotificationsEnabled: json[_pushKey] as bool? ?? true,
      analyticsEnabled: json[_analyticsKey] as bool? ?? false,
      crashReportingEnabled: json[_crashKey] as bool? ?? true,
      personalizedRecommendations: json[_personalizationKey] as bool? ?? true,
    );
  }
}
