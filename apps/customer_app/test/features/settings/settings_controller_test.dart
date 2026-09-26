import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyperlocal_app/core/storage/local_storage_driver.dart';
import 'package:hyperlocal_app/features/settings/domain/models/app_settings.dart';
import 'package:hyperlocal_app/features/settings/presentation/controllers/settings_controller.dart';

void main() {
  group('SettingsController', () {
    late InMemoryStorageDriver driver;
    late ProviderContainer container;

    setUp(() {
      driver = InMemoryStorageDriver();
      container = ProviderContainer(
        overrides: [localStorageDriverProvider.overrideWithValue(driver)],
      );
    });

    tearDown(() {
      container.dispose();
    });

    /// Lets the async hydration microtask run.
    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('has privacy-first defaults', () {
      final settings = container.read(settingsControllerProvider);
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.languageCode, 'en');
      expect(settings.pushNotificationsEnabled, isTrue);
      expect(settings.locationEnabled, isTrue);
      // Privacy: opt-in only.
      expect(settings.analyticsEnabled, isFalse);
      expect(settings.crashReportingEnabled, isTrue);
      expect(settings.personalizedRecommendations, isTrue);
    });

    test('setThemeMode updates and persists themeMode', () async {
      container
          .read(settingsControllerProvider.notifier)
          .setThemeMode(ThemeMode.dark);
      await settle();

      expect(
        container.read(settingsControllerProvider).themeMode,
        ThemeMode.dark,
      );
      final persisted = AppSettings.fromJson(
        jsonDecode(await driver.getString(appSettingsStorageKey) ?? '{}'),
      );
      expect(persisted.themeMode, ThemeMode.dark);
    });

    test('setLanguage updates languageCode to hi and persists', () async {
      container.read(settingsControllerProvider.notifier).setLanguage('hi');
      await settle();

      expect(container.read(settingsControllerProvider).languageCode, 'hi');
      final persisted = AppSettings.fromJson(
        jsonDecode(await driver.getString(appSettingsStorageKey) ?? '{}'),
      );
      expect(persisted.languageCode, 'hi');
    });

    test(
      'toggleNotifications updates push notifications and persists',
      () async {
        container
            .read(settingsControllerProvider.notifier)
            .toggleNotifications(false);
        await settle();

        expect(
          container.read(settingsControllerProvider).pushNotificationsEnabled,
          isFalse,
        );
        final persisted = AppSettings.fromJson(
          jsonDecode(await driver.getString(appSettingsStorageKey) ?? '{}'),
        );
        expect(persisted.pushNotificationsEnabled, isFalse);
      },
    );

    test('privacy toggles persist', () async {
      final controller = container.read(settingsControllerProvider.notifier);
      controller.setAnalytics(true);
      controller.setCrashReporting(false);
      controller.setPersonalizedRecommendations(false);
      await settle();

      final settings = container.read(settingsControllerProvider);
      expect(settings.analyticsEnabled, isTrue);
      expect(settings.crashReportingEnabled, isFalse);
      expect(settings.personalizedRecommendations, isFalse);

      final persisted = AppSettings.fromJson(
        jsonDecode(await driver.getString(appSettingsStorageKey) ?? '{}'),
      );
      expect(persisted.analyticsEnabled, isTrue);
      expect(persisted.crashReportingEnabled, isFalse);
    });

    test('settings hydrate from storage in a fresh session', () async {
      // Simulate a previous session's choices.
      await driver.setString(
        appSettingsStorageKey,
        jsonEncode(
          const AppSettings(
            themeMode: ThemeMode.dark,
            languageCode: 'hi',
            analyticsEnabled: true,
          ).toJson(),
        ),
      );

      final restoredContainer = ProviderContainer(
        overrides: [localStorageDriverProvider.overrideWithValue(driver)],
      );
      addTearDown(restoredContainer.dispose);

      // Trigger build then let hydration complete.
      restoredContainer.read(settingsControllerProvider);
      await restoredContainer.pump();
      await Future<void>.delayed(Duration.zero);

      final settings = restoredContainer.read(settingsControllerProvider);
      expect(settings.themeMode, ThemeMode.dark);
      expect(settings.languageCode, 'hi');
      expect(settings.analyticsEnabled, isTrue);
    });

    test('corrupt stored payload falls back to defaults', () async {
      await driver.setString(appSettingsStorageKey, '{not-json');

      container.read(settingsControllerProvider);
      await container.pump();
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(settingsControllerProvider).themeMode,
        ThemeMode.system,
      );
    });

    test('appStringsProvider reflects selected language', () {
      container.read(settingsControllerProvider.notifier).setLanguage('hi');

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

  group('SharedPreferencesStorageDriver (production default)', () {
    test('persists settings across simulated app restarts', () async {
      SharedPreferences.setMockInitialValues({});

      // "First launch": default provider (SharedPreferences-backed), flip a
      // toggle and let it write through.
      final firstLaunch = ProviderContainer();
      addTearDown(firstLaunch.dispose);
      firstLaunch
          .read(settingsControllerProvider.notifier)
          .toggleNotifications(false);
      await Future<void>.delayed(Duration.zero);

      // "Second launch": a brand-new container over the same underlying
      // SharedPreferences must hydrate the persisted choice.
      final secondLaunch = ProviderContainer();
      addTearDown(secondLaunch.dispose);
      secondLaunch.read(settingsControllerProvider);
      await secondLaunch.pump();
      await Future<void>.delayed(Duration.zero);

      expect(
        secondLaunch.read(settingsControllerProvider).pushNotificationsEnabled,
        isFalse,
        reason:
            'Settings must survive restarts now that the production default '
            'driver persists to SharedPreferences.',
      );
    });
  });
}
