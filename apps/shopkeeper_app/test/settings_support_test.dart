import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/app.dart';
import 'package:hyperlocal_shopkeeper_app/core/auth/firebase_auth_service.dart';
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
}) {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(
        auth ?? (FakeAuthRepository()..restoreResult = makeSession()),
      ),
      firebaseAuthServiceProvider.overrideWithValue(FakeFirebaseAuthService()),
      tokenStoreProvider.overrideWithValue(
        InMemoryTokenStore(accessToken: 'test-access-token'),
      ),
      selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
      dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepo()),
      notificationsRepositoryProvider
          .overrideWithValue(FakeNotificationsRepo()),
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

      expect(find.text('Account settings'), findsOneWidget);
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
}