import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/storage/local_storage_driver.dart';
import 'package:hyperlocal_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_app/features/notifications/data/mock_notification_repository.dart';
import 'package:hyperlocal_app/features/notifications/presentation/controllers/notifications_controller.dart';
import 'package:hyperlocal_app/features/settings/presentation/controllers/settings_controller.dart';
import 'package:hyperlocal_app/features/settings/presentation/screens/settings_screen.dart';

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

  final container = ProviderContainer(overrides: [
    localStorageDriverProvider.overrideWithValue(driver),
    authControllerProvider.overrideWith(() => auth),
    notificationsRepositoryProvider.overrideWithValue(
      MockNotificationRepository(),
    ),
  ]);
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  // Let notification preferences load.
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders all settings sections', (tester) async {
    await _pumpSettings(
      tester,
      driver: InMemoryStorageDriver(),
      auth: _StubAuthController(AuthStatus.authenticated),
    );

    expect(find.text('NOTIFICATIONS'), findsOneWidget);
    expect(find.text('LOCATION PREFERENCES'), findsOneWidget);
    expect(find.text('APP PREFERENCES'), findsOneWidget);
    expect(find.text('PRIVACY & DATA'), findsOneWidget);
    expect(find.text('ACCOUNT'), findsOneWidget);
    // Per-type preference switches from the preferences controller.
    expect(find.byKey(const Key('prefPriceDrop')), findsOneWidget);
    expect(find.byKey(const Key('prefAvailability')), findsOneWidget);
    expect(find.byKey(const Key('prefShopUpdates')), findsOneWidget);
    // Account management entries for signed-in users.
    expect(find.byKey(const Key('deleteAccountTile')), findsOneWidget);
  });

  testWidgets('privacy toggles persist through the storage driver',
      (tester) async {
    final driver = InMemoryStorageDriver();
    await _pumpSettings(
      tester,
      driver: driver,
      auth: _StubAuthController(AuthStatus.authenticated),
    );

    await tester.tap(find.text('Usage analytics'));
    await tester.pumpAndSettle();

    final persisted =
        await driver.getString(appSettingsStorageKey);
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

  testWidgets('sign out requires confirmation and calls the auth controller',
      (tester) async {
    final auth = _StubAuthController(AuthStatus.authenticated);
    await _pumpSettings(
      tester,
      driver: InMemoryStorageDriver(),
      auth: auth,
    );

    await tester.tap(find.byKey(const Key('settingsLogoutTile')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('confirmSettingsLogout')), findsOneWidget);
    expect(auth.logoutCalled, isFalse);

    await tester.tap(find.byKey(const Key('confirmSettingsLogout')));
    await tester.pumpAndSettle();

    expect(auth.logoutCalled, isTrue);
  });

  testWidgets('guests do not see delete-account or edit-profile entries',
      (tester) async {
    await _pumpSettings(
      tester,
      driver: InMemoryStorageDriver(),
      auth: _StubAuthController(AuthStatus.guest),
    );

    expect(find.byKey(const Key('deleteAccountTile')), findsNothing);
    expect(find.text('Edit profile'), findsNothing);
    // Guest exit entry replaces sign out.
    expect(find.text('Exit guest mode'), findsOneWidget);
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

    expect(
      find.text('Clear browsing history?'),
      findsOneWidget,
    );
    // Cancel keeps everything intact.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Browsing history cleared.'), findsNothing);
  });


}
