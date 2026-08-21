import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/app_settings.dart';
import '../../../../core/i18n/app_strings.dart';

final settingsControllerProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

final appStringsProvider = Provider<AppStrings>((ref) {
  final settings = ref.watch(settingsControllerProvider);
  return AppStrings(settings.languageCode);
});

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => const AppSettings();

  void setThemeMode(ThemeMode mode) => state = state.copyWith(themeMode: mode);
  void setLanguage(String code) => state = state.copyWith(languageCode: code);
  void toggleNotifications(bool val) => state = state.copyWith(pushNotificationsEnabled: val);
  void toggleLocation(bool val) => state = state.copyWith(locationEnabled: val);
}