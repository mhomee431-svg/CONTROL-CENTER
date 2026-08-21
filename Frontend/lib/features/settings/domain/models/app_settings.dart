import 'package:flutter/material.dart';

class AppSettings {
  final ThemeMode themeMode;
  final String languageCode; // 'en' or 'hi'
  final bool pushNotificationsEnabled;
  final bool locationEnabled;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.languageCode = 'en',
    this.pushNotificationsEnabled = true,
    this.locationEnabled = true,
  });

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? languageCode,
    bool? pushNotificationsEnabled,
    bool? locationEnabled,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      languageCode: languageCode ?? this.languageCode,
      pushNotificationsEnabled: pushNotificationsEnabled ?? this.pushNotificationsEnabled,
      locationEnabled: locationEnabled ?? this.locationEnabled,
    );
  }
}