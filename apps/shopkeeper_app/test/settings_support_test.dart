import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/app.dart';
import 'package:hyperlocal_shopkeeper_app/features/account/data/sessions_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/account/domain/device_session.dart';
import 'package:hyperlocal_shopkeeper_app/core/auth/firebase_auth_service.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/core/router/app_router.dart';
import 'package:hyperlocal_shopkeeper_app/core/router/route_names.dart';
import 'package:hyperlocal_shopkeeper_app/features/account/presentation/controllers/settings_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/data/dashboard_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/data/notification_preferences_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/data/notifications_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/domain/notification_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/presentation/controllers/notification_preferences_controller.dart';

import 'fakes.dart';

/// Account settings, notification preferences and the support screens.
///
/// The widget tests pump the SHIPPED app (`ShopkeeperApp`) and drive the real
/// router, so a route that is missing, misnamed or unreachable fails here
/// instead of silently doing nothing when a shopkeeper taps it.

/// Container wired for the real app: fakes for every repository the shell can
/// reach, in-memory token + preference stores (no platform channels).
ProviderContainer buildContainer({
  FakeAuthRepository? auth,
  NotificationPreferencesStore? preferences,
  FakeSessionsRepo? sessions,
  String? sessionId,
}) {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(
        auth ?? (FakeAuthRepository()..restoreResult = makeSession()),
      ),
      firebaseAuthServiceProvider.overrideWithValue(FakeFirebaseAuthService()),
      tokenStoreProvider.overrideWithValue(
        InMemoryTokenStore(
          accessToken: 'test-access-token',
          sessionId: sessionId,
        ),
      ),
      selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
      dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepo()),
      notificationsRepositoryProvider
          .overrideWithValue(FakeNotificationsRepo()),
      // Settings → Security reads the device list, so the real app must never
      // reach the network from a widget test.
      sessionsRepositoryProvider.overrideWithValue(sessions ?? FakeSessionsRepo()),
      notificationPreferencesStoreProvider.overrideWithValue(
        preferences ?? InMemoryNotificationPreferencesStore(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Pumps the real app at a phone-sized viewport (the settings lists are long)
/// and waits for the splash-driven session check to settle.
Future<void> pumpApp(WidgetTester tester, ProviderContainer container) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const ShopkeeperApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('NotificationPreferences model', () {
    test('round-trips through JSON with snake_case keys', () {
      const prefs = NotificationPreferences(
        pushEnabled: false,
        smsEnabled: true,
        promotional: true,
      );

      final json = prefs.toJson();

      expect(json['push_enabled'], isFalse);
      expect(json['sms_enabled'], isTrue);
      expect(json['security_alerts'], isTrue);
      expect(NotificationPreferences.fromJson(json), prefs);
    });

    test('missing keys fall back to the documented defaults', () {
      final prefs = NotificationPreferences.fromJson(
        const <String, dynamic>{'promotional': true},
      );

      expect(prefs.pushEnabled, isTrue);
      expect(prefs.smsEnabled, isFalse);
      expect(prefs.promotional, isTrue);
      expect(prefs.securityAlerts, isTrue);
    });
  });

  group('NotificationPreferencesController', () {
    test('loads, edits, discards and saves the preferences', () async {
      final store = InMemoryNotificationPreferencesStore();
      final container = buildContainer(preferences: store);
      await container.read(authControllerProvider.notifier).checkSession();
      final controller =
          container.read(notificationPreferencesProvider.notifier);

      await controller.load();
      expect(
        container.read(notificationPreferencesProvider).status,
        NotificationPreferencesStatus.ready,
      );
      expect(
        container.read(notificationPreferencesProvider).hasUnsavedChanges,
        isFalse,
      );

      controller.update(const NotificationPreferences(pushEnabled: false));
      expect(
        container.read(notificationPreferencesProvider).hasUnsavedChanges,
        isTrue,
      );

      controller.discardChanges();
      expect(
        container.read(notificationPreferencesProvider).hasUnsavedChanges,
        isFalse,
      );

      controller.update(
        const NotificationPreferences(pushEnabled: false, smsEnabled: true),
      );
      expect(await controller.save(), isTrue);

      // Stored under the signed-in user's key, with nothing left pending.
      final stored = await store.read('u1');
      expect(stored?.pushEnabled, isFalse);
      expect(stored?.smsEnabled, isTrue);
      expect(
        container.read(notificationPreferencesProvider).hasUnsavedChanges,
        isFalse,
      );
    });

    test('logout clears the cached delivery preferences', () async {
      final store = InMemoryNotificationPreferencesStore();
      final container = buildContainer(preferences: store);
      await container.read(authControllerProvider.notifier).checkSession();
      final controller =
          container.read(notificationPreferencesProvider.notifier);
      await controller.load();
      controller.update(const NotificationPreferences(pushEnabled: false));
      await controller.save();

      await container.read(authControllerProvider.notifier).logout();

      final state = container.read(notificationPreferencesProvider);
      expect(state.preferences, const NotificationPreferences());
      expect(state.hasUnsavedChanges, isFalse);
    });
  });

  group('SettingsController', () {
    test('theme mode changes take effect immediately', () {
      final container = buildContainer();
      final settings = container.read(settingsControllerProvider.notifier);

      expect(
        container.read(settingsControllerProvider).themeMode,
        ThemeMode.system,
      );

      settings.setThemeMode(ThemeMode.dark);

      expect(
        container.read(settingsControllerProvider).themeMode,
        ThemeMode.dark,
      );
    });

    test('logout runs the single AuthController sign-out flow', () async {
      final auth = FakeAuthRepository()..restoreResult = makeSession();
      final container = buildContainer(auth: auth);
      await container.read(authControllerProvider.notifier).checkSession();

      await container.read(settingsControllerProvider.notifier).logout();

      expect(auth.logoutCalls, 1);
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.unauthenticated,
      );
      // The in-flight flag is always released, even on the happy path.
      expect(container.read(settingsControllerProvider).loggingOut, isFalse);
    });
  });

  group('settings & support screens (real router)', () {
    testWidgets('account settings hub opens the security screen',
        (tester) async {
      final container = buildContainer();
      await pumpApp(tester, container);

      container.read(routerProvider).go(Routes.accountSettings);
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.byKey(const Key('settings_security')), findsOneWidget);
      expect(find.byKey(const Key('settings_edit_profile')), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings_security')));
      await tester.pumpAndSettle();

      expect(find.text('Account protection'), findsOneWidget);
      expect(
        find.byKey(const Key('security_notification_preferences')),
        findsOneWidget,
      );
    });

    testWidgets('app settings rethemes the app', (tester) async {
      final container = buildContainer();
      await pumpApp(tester, container);

      container.read(routerProvider).go(Routes.appSettings);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('theme_option_dark')));
      await tester.pumpAndSettle();

      expect(container.read(settingsControllerProvider).themeMode,
          ThemeMode.dark);
    });

    testWidgets('confirming log out signs the shopkeeper out',
        (tester) async {
      final auth = FakeAuthRepository()..restoreResult = makeSession();
      final container = buildContainer(auth: auth);
      await pumpApp(tester, container);

      container.read(routerProvider).go(Routes.logoutConfirmation);
      await tester.pumpAndSettle();
      expect(find.text('Log out of Passly Business?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('logout_confirm_button')));
      await tester.pumpAndSettle();

      expect(auth.logoutCalls, 1);
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.unauthenticated,
      );
    });

    testWidgets('notification preferences only offer Save after a change',
        (tester) async {
      final store = InMemoryNotificationPreferencesStore();
      final container = buildContainer(preferences: store);
      await pumpApp(tester, container);

      container.read(routerProvider).go(Routes.notificationPreferences);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pref_push_enabled')), findsOneWidget);
      expect(find.byKey(const Key('pref_save_button')), findsNothing);

      await tester.tap(find.byKey(const Key('pref_push_enabled')));
      await tester.pumpAndSettle();

      expect(find.text('You have unsaved changes'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pref_save_button')));
      await tester.pumpAndSettle();

      // Switched OFF by the tap and persisted under the user's key.
      expect((await store.read('u1'))?.pushEnabled, isFalse);
      expect(find.byKey(const Key('pref_save_button')), findsNothing);
    });

    testWidgets('help centre filters its articles by search text',
        (tester) async {
      final container = buildContainer();
      await pumpApp(tester, container);

      container.read(routerProvider).go(Routes.faq);
      await tester.pumpAndSettle();

      expect(find.text('12 of 12 articles'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('faq_search_field')),
        'barcode',
      );
      await tester.pumpAndSettle();

      expect(find.text('1 of 12 articles'), findsOneWidget);
    });

    testWidgets('notification detail without a payload explains itself',
        (tester) async {
      final container = buildContainer();
      await pumpApp(tester, container);

      container.read(routerProvider).go(Routes.notificationDetail);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Open a notification from the Alerts tab to see its details.',
        ),
        findsOneWidget,
      );
    });
  });

  group('DeviceSession', () {
    test('falls back through whatever metadata the backend captured', () {
      expect(deviceSession(sessionId: 's1', deviceName: 'Counter').label,
          'Counter');
      expect(
        deviceSession(sessionId: 's1', deviceName: null, deviceType: 'tablet')
            .label,
        'tablet',
      );
      expect(
        deviceSession(sessionId: 's1',
            deviceName: null, deviceType: null, platform: 'iOS').label,
        'iOS',
      );
      final bare = deviceSession(sessionId: 'abcdefgh12345', withMetadata: false);
      // The raw id is shortened to a usable label, never dumped wholesale.
      expect(bare.label, 'Device abcdefgh');
      expect(bare.detail, 'Device details unavailable');
    });

    test('listFrom keeps only rows the screen can act on', () {
      final rows = DeviceSession.listFrom(<String, dynamic>{
        'sessions': <dynamic>[
          {'session_id': 'a', 'device_name': 'One'},
          // No id: cannot be revoked, so it must not be shown.
          {'device_name': 'no id'},
          'not a map',
          {'session_id': 'b', 'platform': 'Android'},
        ],
      });
      expect(rows.map((session) => session.sessionId).toList(), ['a', 'b']);

      expect(DeviceSession.listFrom(null), isEmpty);
      expect(DeviceSession.listFrom({'sessions': 'nope'}), isEmpty);
    });

    test('parses ISO timestamps and treats junk as absent', () {
      final session = DeviceSession.fromJson(<String, dynamic>{
        'session_id': 'a',
        'last_activity_at': '2026-09-18T21:19:00+00:00',
        'created_at': 'not-a-date',
        'expires_at': '',
      });
      expect(session.lastActivityAt, DateTime.parse('2026-09-18T21:19:00+00:00'));
      expect(session.createdAt, isNull);
      expect(session.expiresAt, isNull);
      expect(session.isValid, isTrue);
    });

    test('an empty id is not a usable session', () {
      expect(DeviceSession.fromJson({'session_id': '  '}).isValid, isFalse);
    });
  });

  group('AppLanguage', () {
    test('only English is bundled in this release', () {
      expect(AppLanguage.values.where((language) => language.isAvailable),
          [AppLanguage.english]);
    });

    test('setLanguage refuses languages whose strings are not bundled', () {
      final container = buildContainer();
      final controller = container.read(settingsControllerProvider.notifier);

      controller.setLanguage(AppLanguage.english);
      expect(container.read(settingsControllerProvider).language,
          AppLanguage.english);

      controller.setLanguage(AppLanguage.hindi);
      expect(container.read(settingsControllerProvider).language,
          AppLanguage.english);
    });

    test('fromCode resolves BCP-47 variants and falls back to English', () {
      expect(AppLanguage.fromCode('en-IN'), AppLanguage.english);
      expect(AppLanguage.fromCode('hi'), AppLanguage.hindi);
      expect(AppLanguage.fromCode('de'), AppLanguage.english);
      expect(AppLanguage.fromCode(null), AppLanguage.english);
    });
  });

  group('Delivery preferences reset (Data & storage)', () {
    test('clearSaved deletes the stored value and returns to defaults',
        () async {
      final store = InMemoryNotificationPreferencesStore();
      await store.write('u1', const NotificationPreferences(pushEnabled: false));
      final container = buildContainer(preferences: store);
      await container.read(authControllerProvider.notifier).checkSession();

      final controller =
          container.read(notificationPreferencesProvider.notifier);
      await controller.load();
      expect(container.read(notificationPreferencesProvider).saved.pushEnabled,
          isFalse);

      expect(await controller.clearSaved(), isTrue);
      expect(await store.read('u1'), isNull);
      expect(container.read(notificationPreferencesProvider).saved,
          const NotificationPreferences());
    });
  });

  group('SETTINGS logical groups', () {
    Future<void> goToSettings(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      container.read(routerProvider).go(Routes.accountSettings);
      await tester.pumpAndSettle();
    }

    /// Brings a row into view — the settings list is taller than the viewport.
    Future<void> scrollTo(WidgetTester tester, Key key) async {
      await tester.scrollUntilVisible(
        find.byKey(key),
        140,
        scrollable: find.byType(Scrollable).first,
      );
    }

    testWidgets('shows the five logical groups in order', (tester) async {
      final container = buildContainer();
      await pumpApp(tester, container);
      await goToSettings(tester, container);

      // The first row of each group; scrolling to it reveals that group's
      // header, so this proves the GROUPS exist, not just the rows.
      const groups = <String, Key>{
        'ACCOUNT': Key('settings_edit_profile'),
        'SECURITY': Key('settings_security'),
        'APP': Key('settings_notification_settings'),
        'LEGAL': Key('settings_privacy'),
        'SUPPORT': Key('settings_help_center'),
      };
      for (final entry in groups.entries) {
        await scrollTo(tester, entry.value);
        expect(find.byKey(entry.value), findsOneWidget);
        expect(find.text(entry.key), findsOneWidget);
      }
    });

    testWidgets('labels the rows exactly as the SETTINGS spec names them',
        (tester) async {
      final container = buildContainer();
      await pumpApp(tester, container);
      await goToSettings(tester, container);

      expect(find.text('My profile'), findsOneWidget);
      expect(find.text('Shop profile'), findsOneWidget);
      expect(find.text('Logout'), findsOneWidget);

      await scrollTo(tester, const Key('settings_sessions'));
      expect(find.text('Authentication'), findsOneWidget);
      expect(find.text('Sessions & devices'), findsOneWidget);

      await scrollTo(tester, const Key('settings_about'));
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Data & storage'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);

      await scrollTo(tester, const Key('settings_privacy'));
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Terms & Conditions'), findsOneWidget);

      await scrollTo(tester, const Key('settings_report_issue'));
      expect(find.text('Help Center'), findsOneWidget);
      expect(find.text('FAQs'), findsOneWidget);
      expect(find.text('Contact Support'), findsOneWidget);
      expect(find.text('Report Issue'), findsOneWidget);
    });

    testWidgets('every group row opens a real screen — no dead taps',
        (tester) async {
      final container = buildContainer(sessionId: 'sess-current');
      await pumpApp(tester, container);

      // Row key name → the AppBar title the destination shows.
      const destinations = <String, String>{
        'settings_edit_profile': 'Edit profile',
        'settings_shop_profile': 'Shop profile',
        'settings_logout': 'Log out of Passly Business?',
        'settings_security': 'Security',
        'settings_sessions': 'Sessions & devices',
        'settings_notification_settings': 'Notification settings',
        'settings_app_settings': 'App settings',
        'settings_language': 'Language',
        'settings_data_storage': 'Data & storage',
        'settings_about': 'About',
        'settings_privacy': 'Privacy policy',
        'settings_terms': 'Terms of service',
        'settings_help_center': 'Help & support',
        'settings_faqs': 'Help centre',
        'settings_contact_support': 'Contact support',
        'settings_report_issue': 'Report an issue',
      };

      for (final entry in destinations.entries) {
        final key = Key(entry.key);
        // Start from the hub each time so the tap always comes from the real
        // row, not from wherever the previous tap left us.
        await goToSettings(tester, container);
        await scrollTo(tester, key);
        await tester.tap(find.byKey(key));
        await tester.pumpAndSettle();

        expect(
          find.text(entry.value),
          findsOneWidget,
          reason: 'tapping ${entry.key} did not open "${entry.value}"',
        );
      }
    });

    testWidgets('Language offers only the bundled language as selectable',
        (tester) async {
      final container = buildContainer();
      await pumpApp(tester, container);

      container.read(routerProvider).go(Routes.language);
      await tester.pumpAndSettle();

      expect(find.text('AVAILABLE NOW'), findsOneWidget);
      expect(find.byKey(const Key('language_option_en')), findsOneWidget);
      // Planned languages are listed but carry no tap target.
      expect(find.text('Coming soon'), findsWidgets);
      expect(find.byKey(const Key('language_pending_hi')), findsOneWidget);

      // A tap on a not-yet-bundled language must not change the app.
      await tester.tap(find.byKey(const Key('language_pending_hi')));
      await tester.pumpAndSettle();
      expect(container.read(settingsControllerProvider).language,
          AppLanguage.english);
    });

    testWidgets('Language shows the current choice from the shared controller',
        (tester) async {
      final container = buildContainer();
      await pumpApp(tester, container);

      container.read(settingsControllerProvider.notifier)
          .setLanguage(AppLanguage.english);
      container.read(routerProvider).go(Routes.language);
      await tester.pumpAndSettle();

      expect(find.text('Currently used by the app'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
    });

    testWidgets('Data & storage reports saved preferences and resets them',
        (tester) async {
      final store = InMemoryNotificationPreferencesStore();
      await store.write('u1', const NotificationPreferences(pushEnabled: false));
      final container = buildContainer(preferences: store);
      await pumpApp(tester, container);

      container.read(routerProvider).go(Routes.dataStorage);
      await tester.pumpAndSettle();

      expect(find.text('Saved for this account'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);

      await tester.tap(find.byKey(const Key('data_storage_reset_preferences')));
      await tester.pumpAndSettle();
      expect(find.text('Reset delivery preferences?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm_reset_preferences')));
      await tester.pumpAndSettle();

      // The value is really gone from device storage, not just from the screen.
      expect(await store.read('u1'), isNull);
      expect(find.text('Using the defaults'), findsOneWidget);
      expect(find.text('Defaults'), findsOneWidget);
      expect(find.text('Delivery preferences reset to their defaults.'),
          findsOneWidget);
    });

    testWidgets('Data & storage links to the device/session screen',
        (tester) async {
      final container = buildContainer(sessionId: 'sess-current');
      await pumpApp(tester, container);

      container.read(routerProvider).go(Routes.dataStorage);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('data_storage_sessions')));
      await tester.pumpAndSettle();

      expect(find.text('Sessions & devices'), findsOneWidget);
    });
  });

  group('Sessions & devices (Settings → Security)', () {
    testWidgets('marks this device and revokes another one', (tester) async {
      final repo = FakeSessionsRepo(
        sessions: [
          deviceSession(sessionId: 'sess-current', deviceName: 'This Pixel'),
          deviceSession(sessionId: 'sess-other', deviceName: 'Counter tablet'),
        ],
      );
      final container =
          buildContainer(sessions: repo, sessionId: 'sess-current');
      await pumpApp(tester, container);

      container.read(routerProvider).go(Routes.sessions);
      await tester.pumpAndSettle();

      expect(find.text('This Pixel'), findsOneWidget);
      expect(find.text('Counter tablet'), findsOneWidget);
      expect(find.text('This device'), findsOneWidget);
      // The current device has no revoke button: Logout owns ending THIS
      // session, so the screen cannot sign the user out without warning.
      expect(find.byKey(const Key('revoke_session_sess-current')), findsNothing);

      await tester.tap(find.byKey(const Key('revoke_session_sess-other')));
      await tester.pumpAndSettle();
      expect(find.text('Sign out this device?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm_revoke_session')));
      await tester.pumpAndSettle();

      expect(repo.revoked, ['sess-other']);
      // The list is re-read from the server, so the device is really gone.
      expect(find.text('Counter tablet'), findsNothing);
      expect(find.text('This Pixel'), findsOneWidget);
    });

    testWidgets('a failed revoke is explained and the device stays listed',
        (tester) async {
      final repo = FakeSessionsRepo(
        sessions: [
          deviceSession(sessionId: 'sess-current'),
          deviceSession(sessionId: 'sess-other', deviceName: 'Counter tablet'),
        ],
        revokeError: const ApiException(message: 'Session not found'),
      );
      final container =
          buildContainer(sessions: repo, sessionId: 'sess-current');
      await pumpApp(tester, container);

      container.read(routerProvider).go(Routes.sessions);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('revoke_session_sess-other')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_revoke_session')));
      await tester.pumpAndSettle();

      expect(repo.revoked, isEmpty);
      expect(find.text('Session not found'), findsOneWidget);
      expect(find.text('Counter tablet'), findsOneWidget);
    });

    testWidgets('explains an account the backend has no session row for',
        (tester) async {
      final container = buildContainer(sessions: FakeSessionsRepo());
      await pumpApp(tester, container);

      container.read(routerProvider).go(Routes.sessions);
      await tester.pumpAndSettle();

      expect(find.text('No device sessions recorded'), findsOneWidget);
    });

    testWidgets('a load failure is retryable', (tester) async {
      final repo = FakeSessionsRepo(
        error: const ApiException(message: 'backend unreachable'),
      );
      final container =
          buildContainer(sessions: repo, sessionId: 'sess-current');
      await pumpApp(tester, container);

      container.read(routerProvider).go(Routes.sessions);
      await tester.pumpAndSettle();

      expect(find.text('backend unreachable'), findsOneWidget);

      repo.error = null;
      repo.sessions = [deviceSession(sessionId: 'sess-current')];
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('session_this_device')), findsOneWidget);
    });
  });
}