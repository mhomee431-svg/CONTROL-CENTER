import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_customer_app/features/settings/presentation/controllers/settings_controller.dart';

void main() {
  group('SettingsController', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('has default settings', () {
      final state = container.read(settingsControllerProvider);
      expect(state.themeMode, ThemeMode.system);
      expect(state.languageCode, 'en');
      expect(state.pushNotificationsEnabled, isTrue);
      expect(state.locationEnabled, isTrue);
    });

    test('setThemeMode updates themeMode', () {
      final controller = container.read(settingsControllerProvider.notifier);
      controller.setThemeMode(ThemeMode.dark);

      expect(container.read(settingsControllerProvider).themeMode, ThemeMode.dark);
    });

    test('setLanguage updates languageCode to hi', () {
      final controller = container.read(settingsControllerProvider.notifier);
      controller.setLanguage('hi');

      expect(container.read(settingsControllerProvider).languageCode, 'hi');
    });

    test('toggleNotifications updates push notifications', () {
      final controller = container.read(settingsControllerProvider.notifier);
      controller.toggleNotifications(false);

      expect(container.read(settingsControllerProvider).pushNotificationsEnabled, isFalse);
    });

    test('toggleLocation updates location enabled', () {
      final controller = container.read(settingsControllerProvider.notifier);
      controller.toggleLocation(false);

      expect(container.read(settingsControllerProvider).locationEnabled, isFalse);
    });

    test('appStringsProvider reflects selected language', () {
      final controller = container.read(settingsControllerProvider.notifier);
      controller.setLanguage('hi');

      final strings = container.read(appStringsProvider);
      expect(strings.get('settingsTitle'), 'सेटिंग्स');
      expect(strings.get('language'), 'भाषा');
    });

    test('appStringsProvider defaults to English', () {
      final strings = container.read(appStringsProvider);
      expect(strings.get('settingsTitle'), 'Settings');
      expect(strings.get('theme'), 'Theme');
    });
  });
}