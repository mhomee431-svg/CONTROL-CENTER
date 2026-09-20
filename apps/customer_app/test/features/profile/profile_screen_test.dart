import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_app/features/profile/data/mock_profile_repository.dart';
import 'package:hyperlocal_app/features/profile/presentation/controllers/profile_controller.dart';
import 'package:hyperlocal_app/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:hyperlocal_app/features/profile/presentation/screens/profile_screen.dart';

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
        builder: (_, _) => const Scaffold(body: Text('AddressesPage')),
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
  testWidgets('guest sees sign-in prompt instead of profile data',
      (tester) async {
    final auth = _StubAuthController(AuthStatus.guest);
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(() => auth),
    ]);
    addTearDown(container.dispose);

    await pump(tester, container);

    expect(find.text('You are browsing as a guest'), findsOneWidget);
    expect(find.byKey(const Key('guestSignInButton')), findsOneWidget);
    // Guests keep access to local features and can leave guest mode.
    expect(find.byKey(const Key('addressesTile')), findsOneWidget);
    expect(find.text('Exit guest mode'), findsOneWidget);
    expect(find.byKey(const Key('editProfileButton')), findsNothing);
  });

  testWidgets('authenticated user sees profile info and account sections',
      (tester) async {
    final auth = _StubAuthController(AuthStatus.authenticated);
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(() => auth),
      profileRepositoryProvider.overrideWithValue(MockProfileRepository()),
    ]);
    addTearDown(container.dispose);

    await pump(tester, container);

    expect(find.text('Rahul Sharma'), findsOneWidget);
    expect(find.text('rahul.sharma@example.com'), findsOneWidget);
    expect(find.byKey(const Key('editProfileButton')), findsOneWidget);
    expect(find.byKey(const Key('addressesTile')), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
  });

  testWidgets('logout requires confirmation and signs out via auth controller',
      (tester) async {
    final auth = _StubAuthController(AuthStatus.authenticated);
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(() => auth),
      profileRepositoryProvider.overrideWithValue(MockProfileRepository()),
    ]);
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
  });

  testWidgets('addresses tile navigates to the address book', (tester) async {
    final auth = _StubAuthController(AuthStatus.guest);
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(() => auth),
    ]);
    addTearDown(container.dispose);

    await pump(tester, container);

    await tester.tap(find.byKey(const Key('addressesTile')));
    await tester.pumpAndSettle();

    expect(find.text('AddressesPage'), findsOneWidget);
  });

  testWidgets('edit profile rejects invalid email and saves valid input',
      (tester) async {
    final auth = _StubAuthController(AuthStatus.authenticated);
    final repository = MockProfileRepository();
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(() => auth),
      profileRepositoryProvider.overrideWithValue(repository),
    ]);
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
        find.byKey(const Key('phoneField')), '+91 98765 43210');
    await tester.tap(find.byKey(const Key('saveProfileButton')));
    await tester.pump();

    expect(find.text('Please enter a valid email address.'), findsOneWidget);

    // Fixing the input allows saving and pops back to the profile.
    await tester.enterText(
        find.byKey(const Key('emailField')), 'priya@example.com');
    await tester.tap(find.byKey(const Key('saveProfileButton')));
    await tester.pumpAndSettle();

    expect(find.text('Profile updated.'), findsOneWidget);
    final saved = container.read(profileControllerProvider).value!;
    expect(saved.name, 'Priya Verma');
    expect(saved.email, 'priya@example.com');
  });


}

