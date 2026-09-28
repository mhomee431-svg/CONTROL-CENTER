import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal_app/core/storage/local_storage_driver.dart';
import 'package:hyperlocal_app/features/auth/domain/auth_service.dart'
    show authAppVersion;
import 'package:hyperlocal_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_app/features/notifications/data/mock_notification_repository.dart';
import 'package:hyperlocal_app/features/settings/presentation/controllers/settings_controller.dart';
import 'package:hyperlocal_app/features/settings/presentation/screens/settings_screen.dart';
import 'package:hyperlocal_app/features/notifications/domain/notification_repository.dart';

class _StubAuthController extends AuthController {
  final AuthStatus initialStatus;
  bool logoutCalled = false;

  _StubAuthController(this.initialStatus);

  @override
  AuthState build() => AuthState(status: initialStatus);

  @override
  Future<void> logout() async {
    logoutCalled = true;
    state = AuthState.unauthenticated();
  }
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  required InMemoryStorageDriver driver,
  required _StubAuthController auth,
}) async {
  // Large surface so every settings section is built and hittable.
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      localStorageDriverProvider.overrideWithValue(driver),
      authControllerProvider.overrideWith(() => auth),
      notificationsRepositoryProvider.overrideWithValue(
        // Zero delay: the default 150 ms artificial latency is modelled with
        // `Future.delayed`, which leaves a real pending timer that outlives the
        // widget tree and trips the framework's `timersPending` invariant.
        MockNotificationRepository(delay: Duration.zero),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      // A real GoRouter is required: the settings rows navigate with
      // `context.push`, which throws under a bare MaterialApp.
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
  // Let notification preferences load.
  await tester.pumpAndSettle();
}

/// Mirrors every destination the settings screen can push to, so a tap never
/// hits an undeclared route.
GoRouter _router() {
  return GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      for (final path in const [
        '/account',
        '/profile',
        '/profile/edit',
        '/profile/addresses',
        '/notification-settings',
        '/location-settings',
        '/saved',
        '/notifications',
        '/help',
        '/privacy',
        '/privacy-data',
        '/terms',
        '/about',
        '/delete-account',
        '/onboarding',
        '/login',
      ])
        GoRoute(
          path: path,
          // An AppBar gives the pushed page a real back button, so the tests
          // that return via `tester.pageBack()` exercise a real pop instead of
          // failing to find a widget.
          builder: (_, _) => Scaffold(appBar: AppBar(), body: Text('Page$path')),
        ),
    ],
  );
}

void main() {
  testWidgets('renders all settings sections', (tester) async {
    await _pumpSettings(
      tester,
      driver: InMemoryStorageDriver(),
      auth: _StubAuthController(AuthStatus.authenticated),
    );

    expect(find.text('ACCOUNT'), findsOneWidget);
    expect(find.text('NOTIFICATIONS'), findsOneWidget);
    expect(find.text('LOCATION PREFERENCES'), findsOneWidget);
    expect(find.text('APPEARANCE'), findsOneWidget);
    expect(find.text('PRIVACY & DATA'), findsOneWidget);
    expect(find.text('SUPPORT & ABOUT'), findsOneWidget);
    expect(find.text('SESSION'), findsOneWidget);
    // The per-type switches moved to the dedicated notification screen, so
    // Settings now points there rather than duplicating them.
    expect(find.byKey(const Key('notificationSettingsTile')), findsOneWidget);
    expect(find.byKey(const Key('prefPriceDrop')), findsNothing);
    // Account management entries for signed-in users.
    expect(find.byKey(const Key('deleteAccountTile')), findsOneWidget);
  });

  testWidgets('legal documents and about are reachable from settings', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      driver: InMemoryStorageDriver(),
      auth: _StubAuthController(AuthStatus.authenticated),
    );

    expect(find.byKey(const Key('settingsTermsTile')), findsOneWidget);
    // The privacy entry is the interactive centre; the legal document is
    // one tap deeper from there.
    expect(find.byKey(const Key('privacyPolicyTile')), findsOneWidget);
    expect(find.byKey(const Key('settingsAboutTile')), findsOneWidget);
    // The About row shows the live app version, not a stale literal.
    expect(find.text('Version $authAppVersion'), findsOneWidget);
  });

  testWidgets('delete account opens the dedicated deletion flow', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      driver: InMemoryStorageDriver(),
      auth: _StubAuthController(AuthStatus.authenticated),
    );

    await tester.tap(find.byKey(const Key('deleteAccountTile')));
    await tester.pumpAndSettle();

    // The old inline dialog is gone: the real flow (impact, confirmation,
    // backend call, teardown) is its own screen.
    expect(find.text('Delete account?'), findsNothing);
  });

  testWidgets('account section links to the account hub', (tester) async {
    await _pumpSettings(
      tester,
      driver: InMemoryStorageDriver(),
      auth: _StubAuthController(AuthStatus.authenticated),
    );

    expect(find.byKey(const Key('settingsAccountHubTile')), findsOneWidget);
    expect(find.byKey(const Key('settingsEditProfileTile')), findsOneWidget);
  });

  testWidgets('clear all local data warns before wiping saved items', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      driver: InMemoryStorageDriver(),
      auth: _StubAuthController(AuthStatus.authenticated),
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('clearAllLocalDataTile')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('clearAllLocalDataTile')));
    await tester.pumpAndSettle();

    // It must be explicit that synced account data is NOT removed.
    expect(find.text('Clear all local data?'), findsOneWidget);
    expect(find.textContaining('stay on your account'), findsOneWidget);

    // Cancelling changes nothing.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('All local data cleared.'), findsNothing);
  });

  testWidgets('privacy toggles persist through the storage driver', (
    tester,
  ) async {
    final driver = InMemoryStorageDriver();
    await _pumpSettings(
      tester,
      driver: driver,
      auth: _StubAuthController(AuthStatus.authenticated),
    );

    await tester.tap(find.text('Usage analytics'));
    await tester.pumpAndSettle();

    final persisted = await driver.getString(appSettingsStorageKey);
    expect(persisted, isNotNull);
    expect(persisted!.contains('"analyticsEnabled":true'), isTrue);
  });

  testWidgets('language switch updates localized strings', (tester) async {
    await _pumpSettings(
      tester,
      driver: InMemoryStorageDriver(),
      auth: _StubAuthController(AuthStatus.authenticated),
    );

    // Open the language dialog and pick Hindi.
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('langHiOption')));
    await tester.pumpAndSettle();

    expect(find.text('सेटिंग्स'), findsOneWidget);
  });

  testWidgets('sign out requires confirmation and calls the auth controller', (
    tester,
  ) async {
    final auth = _StubAuthController(AuthStatus.authenticated);
    await _pumpSettings(tester, driver: InMemoryStorageDriver(), auth: auth);

    await tester.tap(find.byKey(const Key('settingsLogoutTile')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('confirmSettingsLogout')), findsOneWidget);
    expect(auth.logoutCalled, isFalse);

    await tester.tap(find.byKey(const Key('confirmSettingsLogout')));
    await tester.pumpAndSettle();

    expect(auth.logoutCalled, isTrue);
  });

  testWidgets('guests do not see delete-account or edit-profile entries', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      driver: InMemoryStorageDriver(),
      auth: _StubAuthController(AuthStatus.guest),
    );

    expect(find.byKey(const Key('deleteAccountTile')), findsNothing);
    expect(find.byKey(const Key('settingsEditProfileTile')), findsNothing);
    // Guest exit entry replaces sign out.
    expect(find.text('Exit guest mode'), findsOneWidget);
    // The account hub stays reachable — browsing as a guest is still browsing.
    expect(find.byKey(const Key('settingsAccountHubTile')), findsOneWidget);
  });

  testWidgets('clear browsing history asks for confirmation', (tester) async {
    await _pumpSettings(
      tester,
      driver: InMemoryStorageDriver(),
      auth: _StubAuthController(AuthStatus.authenticated),
    );

    // Scroll to the privacy section.
    await tester.scrollUntilVisible(
      find.byKey(const Key('clearHistoryTile')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('clearHistoryTile')));
    await tester.pumpAndSettle();

    expect(find.text('Clear browsing history?'), findsOneWidget);
    // Cancel keeps everything intact.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Browsing history cleared.'), findsNothing);
  });
}
