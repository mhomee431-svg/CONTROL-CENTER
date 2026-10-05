import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal_app/core/storage/local_storage_driver.dart';
import 'package:hyperlocal_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_app/features/profile/domain/models/user_profile.dart';
import 'package:hyperlocal_app/features/profile/domain/profile_repository.dart';
import 'package:hyperlocal_app/features/profile/presentation/screens/privacy_screen.dart';

class _StubAuthController extends AuthController {
  final AuthStatus status;

  _StubAuthController(this.status);

  @override
  AuthState build() => AuthState(status: status);
}

class _FailingProfileRepo implements ProfileRepository {
  @override
  Future<UserProfile> getProfile() async => throw Exception('offline');

  @override
  Future<UserProfile> updateProfile({
    required String name,
    required String email,
    required String phoneNumber,
  }) async => throw Exception('offline');

  @override
  Future<void> deleteAccount() async {}
}

GoRouter _router() {
  return GoRouter(
    initialLocation: '/privacy-data',
    routes: [
      GoRoute(path: '/privacy-data', builder: (_, _) => const PrivacyScreen()),
      GoRoute(
        path: '/privacy',
        builder: (_, _) =>
            Scaffold(appBar: AppBar(), body: const Text('PolicyDocument')),
      ),
      GoRoute(
        path: '/location-settings',
        builder: (_, _) => Scaffold(
          appBar: AppBar(),
          body: const Text('LocationSettingsPage'),
        ),
      ),
      GoRoute(
        path: '/notification-settings',
        builder: (_, _) => Scaffold(
          appBar: AppBar(),
          body: const Text('NotificationSettingsPage'),
        ),
      ),
      GoRoute(
        path: '/delete-account',
        builder: (_, _) =>
            Scaffold(appBar: AppBar(), body: const Text('DeleteAccountPage')),
      ),
    ],
  );
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  AuthStatus status = AuthStatus.authenticated,
}) async {
  tester.view.physicalSize = const Size(1080, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      localStorageDriverProvider.overrideWithValue(InMemoryStorageDriver()),
      authControllerProvider.overrideWith(() => _StubAuthController(status)),
      profileRepositoryProvider.overrideWithValue(_FailingProfileRepo()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('includes all five required privacy areas', (tester) async {
    await _pump(tester);

    // 1. Privacy Policy
    expect(find.byKey(const Key('privacyPolicyLink')), findsOneWidget);
    // 2. Data use explanation
    expect(find.text('What we collect'), findsOneWidget);
    expect(find.text('What we do with it'), findsOneWidget);
    // 3. Location usage information
    expect(find.text('How location is used'), findsOneWidget);
    // 4. Notification preferences
    expect(
      find.byKey(const Key('privacyNotificationSettingsLink')),
      findsOneWidget,
    );
    // 5. Account deletion
    expect(find.byKey(const Key('privacyDeleteAccountTile')), findsOneWidget);
  });

  testWidgets('makes no absolute privacy promises the app cannot keep', (
    tester,
  ) async {
    await _pump(tester);

    // "We do not sell your personal data" is a true, checkable claim.
    expect(
      find.textContaining('We do not sell your personal data'),
      findsOneWidget,
    );
    // But the screen must also disclose what is actually collected — a
    // screen that only made reassuring claims would itself be misleading.
    expect(
      find.textContaining('the products and shops you search'),
      findsOneWidget,
    );
    // And it must not claim we collect nothing at all.
    expect(find.textContaining('we never collect'), findsNothing);
    expect(find.textContaining('no data is collected'), findsNothing);
  });

  testWidgets('location settings and notification preferences are linked', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('privacyLocationSettingsLink')));
    await tester.pumpAndSettle();
    expect(find.text('LocationSettingsPage'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('privacyNotificationSettingsLink')));
    await tester.pumpAndSettle();
    expect(find.text('NotificationSettingsPage'), findsOneWidget);
  });

  testWidgets('the privacy policy document is one tap away', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('privacyPolicyLink')));
    await tester.pumpAndSettle();
    expect(find.text('PolicyDocument'), findsOneWidget);
  });

  testWidgets('guests are not offered account deletion', (tester) async {
    await _pump(tester, status: AuthStatus.guest);

    expect(find.byKey(const Key('privacyDeleteAccountTile')), findsNothing);
    expect(find.text('Signed out'), findsOneWidget);
    // The read-only information is still there.
    expect(find.text('What we collect'), findsOneWidget);
  });

  testWidgets('delete account opens the real deletion flow', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('privacyDeleteAccountTile')));
    await tester.pumpAndSettle();
    // Not a dialog — the full multi-step flow lives on its own screen.
    expect(find.text('DeleteAccountPage'), findsOneWidget);
  });

  testWidgets('analytics is a real, off-by-default control', (tester) async {
    await _pump(tester);

    final tile = tester.widget<SwitchListTile>(
      find.byKey(const Key('privacyAnalyticsSwitch')),
    );
    expect(tile.value, isFalse);
    // The label says "off by default" rather than burying it.
    expect(find.textContaining('Off by default'), findsOneWidget);
  });
}
