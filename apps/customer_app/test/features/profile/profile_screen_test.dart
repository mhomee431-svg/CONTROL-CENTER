import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_app/features/profile/data/mock_profile_repository.dart';
import 'package:hyperlocal_app/features/profile/presentation/controllers/profile_controller.dart';
import 'package:hyperlocal_app/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:hyperlocal_app/features/profile/presentation/screens/profile_screen.dart';
import 'package:hyperlocal_app/features/profile/domain/profile_repository.dart';

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

GoRouter _router() {
  return GoRouter(
    initialLocation: '/profile',
    routes: [
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      GoRoute(
        path: '/profile/edit',
        builder: (_, _) => const EditProfileScreen(),
      ),
      GoRoute(
        path: '/profile/addresses',
        builder: (_, _) => Scaffold(appBar: AppBar(), body: const Text('AddressesPage')),
      ),
      GoRoute(
        path: '/help',
        builder: (_, _) => Scaffold(appBar: AppBar(), body: const Text('HelpPage')),
      ),
      GoRoute(
        path: '/privacy',
        builder: (_, _) => Scaffold(appBar: AppBar(), body: const Text('PrivacyPage')),
      ),
      GoRoute(
        path: '/terms',
        builder: (_, _) => Scaffold(appBar: AppBar(), body: const Text('TermsPage')),
      ),
      GoRoute(
        path: '/account',
        builder: (_, _) => Scaffold(appBar: AppBar(), body: const Text('AccountHubPage')),
      ),
      GoRoute(
        path: '/delete-account',
        builder: (_, _) => Scaffold(appBar: AppBar(), body: const Text('DeleteAccountPage')),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, state) => Scaffold(
          body: Text('SettingsPage:${state.uri.queryParameters['section']}'),
        ),
      ),
    ],
  );
}

Future<void> pump(WidgetTester tester, ProviderContainer container) async {
  // Large surface so every account section is built and hittable.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('guest sees sign-in prompt instead of profile data', (
    tester,
  ) async {
    final auth = _StubAuthController(AuthStatus.guest);
    final container = ProviderContainer(
      overrides: [authControllerProvider.overrideWith(() => auth)],
    );
    addTearDown(container.dispose);

    await pump(tester, container);

    expect(find.text('You are browsing as a guest'), findsOneWidget);
    expect(find.byKey(const Key('guestSignInButton')), findsOneWidget);
    // Guests keep access to local features and can leave guest mode.
    expect(find.byKey(const Key('addressesTile')), findsOneWidget);
    expect(find.text('Exit guest mode'), findsOneWidget);
    expect(find.byKey(const Key('editProfileButton')), findsNothing);
  });

  testWidgets('authenticated user sees profile info and account sections', (
    tester,
  ) async {
    final auth = _StubAuthController(AuthStatus.authenticated);
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(() => auth),
        profileRepositoryProvider.overrideWithValue(MockProfileRepository()),
      ],
    );
    addTearDown(container.dispose);

    await pump(tester, container);

    expect(find.text('Rahul Sharma'), findsOneWidget);
    expect(find.text('rahul.sharma@example.com'), findsOneWidget);
    expect(find.byKey(const Key('editProfileButton')), findsOneWidget);
    expect(find.byKey(const Key('addressesTile')), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
  });

  testWidgets(
    'logout requires confirmation and signs out via auth controller',
    (tester) async {
      final auth = _StubAuthController(AuthStatus.authenticated);
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(() => auth),
          profileRepositoryProvider.overrideWithValue(MockProfileRepository()),
        ],
      );
      addTearDown(container.dispose);

      await pump(tester, container);

      await tester.tap(find.byKey(const Key('logoutButton')));
      await tester.pumpAndSettle();

      // Confirmation dialog is shown first.
      expect(find.byKey(const Key('confirmLogout')), findsOneWidget);
      expect(auth.logoutCalled, isFalse);

      await tester.tap(find.byKey(const Key('confirmLogout')));
      await tester.pumpAndSettle();

      expect(auth.logoutCalled, isTrue);
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.unauthenticated,
      );
    },
  );

  testWidgets('addresses tile navigates to the address book', (tester) async {
    final auth = _StubAuthController(AuthStatus.guest);
    final container = ProviderContainer(
      overrides: [authControllerProvider.overrideWith(() => auth)],
    );
    addTearDown(container.dispose);

    await pump(tester, container);

    await tester.tap(find.byKey(const Key('addressesTile')));
    await tester.pumpAndSettle();

    expect(find.text('AddressesPage'), findsOneWidget);
  });

  testWidgets('every spec entry is present for a signed-in customer', (
    tester,
  ) async {
    final auth = _StubAuthController(AuthStatus.authenticated);
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(() => auth),
        profileRepositoryProvider.overrideWithValue(MockProfileRepository()),
      ],
    );
    addTearDown(container.dispose);

    await pump(tester, container);

    // Identity
    expect(find.text('Rahul Sharma'), findsOneWidget); // Full name
    expect(find.text('rahul.sharma@example.com'), findsOneWidget); // Email
    expect(find.text('+91 98765 43210'), findsOneWidget); // Mobile
    // Entries
    expect(find.byKey(const Key('addressesTile')), findsOneWidget);
    expect(find.byKey(const Key('notificationsSettingsTile')), findsOneWidget);
    expect(find.byKey(const Key('appSettingsTile')), findsOneWidget);
    expect(find.byKey(const Key('privacyTile')), findsOneWidget);
    expect(find.byKey(const Key('termsTile')), findsOneWidget);
    expect(find.byKey(const Key('helpSupportTile')), findsOneWidget);
    expect(find.byKey(const Key('logoutButton')), findsOneWidget);
    expect(find.byKey(const Key('deleteAccountTile')), findsOneWidget);
  });

  testWidgets('no internal identifiers are rendered anywhere', (tester) async {
    final auth = _StubAuthController(AuthStatus.authenticated);
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(() => auth),
        profileRepositoryProvider.overrideWithValue(MockProfileRepository()),
      ],
    );
    addTearDown(container.dispose);

    await pump(tester, container);

    // The mock profile's id is "1" — it must never surface as user-facing text.
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final value = text.data?.toLowerCase() ?? '';
      expect(value.contains('user id'), isFalse);
      expect(value.contains('customer id'), isFalse);
      expect(value.contains('uuid'), isFalse);
    }
  });

  testWidgets('privacy opens the privacy document, not the help page', (
    tester,
  ) async {
    final auth = _StubAuthController(AuthStatus.authenticated);
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(() => auth),
        profileRepositoryProvider.overrideWithValue(MockProfileRepository()),
      ],
    );
    addTearDown(container.dispose);

    await pump(tester, container);
    await tester.tap(find.byKey(const Key('privacyTile')));
    await tester.pumpAndSettle();

    expect(find.text('PrivacyPage'), findsOneWidget);
    expect(find.text('HelpPage'), findsNothing);
  });

  testWidgets('terms opens the terms document', (tester) async {
    final auth = _StubAuthController(AuthStatus.authenticated);
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(() => auth),
        profileRepositoryProvider.overrideWithValue(MockProfileRepository()),
      ],
    );
    addTearDown(container.dispose);

    await pump(tester, container);
    await tester.tap(find.byKey(const Key('termsTile')));
    await tester.pumpAndSettle();

    expect(find.text('TermsPage'), findsOneWidget);
  });

  testWidgets('notifications deep-links to the notifications section', (
    tester,
  ) async {
    final auth = _StubAuthController(AuthStatus.authenticated);
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(() => auth),
        profileRepositoryProvider.overrideWithValue(MockProfileRepository()),
      ],
    );
    addTearDown(container.dispose);

    await pump(tester, container);
    await tester.tap(find.byKey(const Key('notificationsSettingsTile')));
    await tester.pumpAndSettle();

    expect(find.text('SettingsPage:notifications'), findsOneWidget);
  });

  testWidgets('delete account hands off to the dedicated flow', (
    tester,
  ) async {
    final auth = _StubAuthController(AuthStatus.authenticated);
    final repository = MockProfileRepository(delay: Duration.zero);
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(() => auth),
        profileRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await pump(tester, container);
    await tester.tap(find.byKey(const Key('deleteAccountTile')));
    await tester.pumpAndSettle();

    // The old inline confirm dialog is gone. Tapping the entry must not
    // delete anything by itself — the real flow (impact -> confirm ->
    // backend call -> teardown) lives on its own screen and is covered by
    // delete_account_screen_test.dart.
    expect(find.byKey(const Key('confirmDeleteAccount')), findsNothing);
    expect(repository.isDeleted, isFalse);
    expect(auth.logoutCalled, isFalse);
  });

  testWidgets('leaving the profile screen does not delete the account', (
    tester,
  ) async {
    final auth = _StubAuthController(AuthStatus.authenticated);
    final repository = MockProfileRepository(delay: Duration.zero);
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(() => auth),
        profileRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await pump(tester, container);
    // Navigating away without confirming must leave everything intact.
    await tester.tap(find.byKey(const Key('editProfileButton')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(repository.isDeleted, isFalse);
    expect(auth.logoutCalled, isFalse);
  });

  testWidgets('guests are not offered destructive account actions', (
    tester,
  ) async {
    final auth = _StubAuthController(AuthStatus.guest);
    final container = ProviderContainer(
      overrides: [authControllerProvider.overrideWith(() => auth)],
    );
    addTearDown(container.dispose);

    await pump(tester, container);

    expect(find.byKey(const Key('deleteAccountTile')), findsNothing);
    // Read-only legal/help entries remain available.
    expect(find.byKey(const Key('privacyTile')), findsOneWidget);
    expect(find.byKey(const Key('termsTile')), findsOneWidget);
  });

  testWidgets('edit profile rejects invalid email and saves valid input', (
    tester,
  ) async {
    final auth = _StubAuthController(AuthStatus.authenticated);
    final repository = MockProfileRepository();
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(() => auth),
        profileRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    // Pre-load the profile so the edit form initializes with values.
    container.read(profileControllerProvider.notifier);
    await container.pump();

    await pump(tester, container);
    await tester.tap(find.byKey(const Key('editProfileButton')));
    await tester.pumpAndSettle();

    expect(find.byType(EditProfileScreen), findsOneWidget);

    // Invalid email keeps the user on screen with an error.
    await tester.enterText(find.byKey(const Key('nameField')), 'Priya Verma');
    await tester.enterText(find.byKey(const Key('emailField')), 'not-an-email');
    await tester.enterText(
      find.byKey(const Key('phoneField')),
      '+91 98765 43210',
    );
    await tester.tap(find.byKey(const Key('saveProfileButton')));
    await tester.pump();

    expect(find.text('Please enter a valid email address.'), findsOneWidget);

    // Fixing the input allows saving and pops back to the profile.
    await tester.enterText(
      find.byKey(const Key('emailField')),
      'priya@example.com',
    );
    await tester.tap(find.byKey(const Key('saveProfileButton')));
    await tester.pumpAndSettle();

    expect(find.text('Profile updated.'), findsOneWidget);
    final saved = container.read(profileControllerProvider).value!;
    expect(saved.name, 'Priya Verma');
    expect(saved.email, 'priya@example.com');
  });
}
