import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_app/features/notifications/data/mock_notification_repository.dart';
import 'package:hyperlocal_app/features/notifications/domain/notification_repository.dart';
import 'package:hyperlocal_app/features/notifications/presentation/controllers/notifications_controller.dart';
import 'package:hyperlocal_app/features/profile/data/mock_profile_repository.dart';
import 'package:hyperlocal_app/features/profile/domain/models/user_profile.dart';
import 'package:hyperlocal_app/features/profile/domain/profile_repository.dart';
import 'package:hyperlocal_app/features/profile/presentation/screens/account_screen.dart';
import 'package:hyperlocal_app/features/saved_and_history/presentation/screens/saved_items_screen.dart';

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

/// Profile repository that always fails, to prove the account menu stays
/// usable when the identity header cannot load.
class _FailingProfileRepository implements ProfileRepository {
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

/// Mirrors the real destination of every account entry, so a mis-wired
/// onTap fails the test instead of silently doing nothing.
GoRouter _router() {
  return GoRouter(
    initialLocation: '/account',
    routes: [
      GoRoute(path: '/account', builder: (_, _) => const AccountScreen()),
      GoRoute(
        path: '/profile',
        builder: (_, _) => Scaffold(appBar: AppBar(), body: const Text('ProfilePage')),
      ),
      GoRoute(
        path: '/profile/addresses',
        builder: (_, _) => Scaffold(appBar: AppBar(), body: const Text('AddressesPage')),
      ),
      GoRoute(
        path: '/saved',
        builder: (_, state) => Scaffold(
          appBar: AppBar(),
          body: Text('SavedPage:${state.uri.queryParameters['tab']}'),
        ),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => Scaffold(appBar: AppBar(), body: const Text('NotificationsPage')),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => Scaffold(appBar: AppBar(), body: const Text('SettingsPage')),
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
    ],
  );
}

Future<ProviderContainer> pump(
  WidgetTester tester,
  AuthStatus status, {
  ProfileRepository? profileRepository,
  // The stub is a test-local detail; exposing its public name would only widen
  // the surface for no benefit. Private type in a private-test helper is safe.
  // ignore: library_private_types_in_public_api
  _StubAuthController? authOverride,
}) async {
  // Tall surface so every account row is built and hittable.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith(
        () => authOverride ?? _StubAuthController(status),
      ),
      profileRepositoryProvider.overrideWithValue(
        profileRepository ?? MockProfileRepository(delay: Duration.zero),
      ),
      notificationsRepositoryProvider.overrideWithValue(
        MockNotificationRepository(delay: Duration.zero),
      ),
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
  testWidgets('lists every account entry from the specification', (
    tester,
  ) async {
    await pump(tester, AuthStatus.authenticated);

    expect(find.text('Account'), findsOneWidget);
    for (final label in [
      'Profile',
      'Saved Products',
      'Saved Shops',
      'Search History',
      'Saved Addresses',
      'Notifications',
      'Settings',
      'Help',
      'Privacy',
      'Terms',
    ]) {
      expect(find.text(label), findsOneWidget, reason: 'missing "$label"');
    }
    expect(find.text('Log out'), findsOneWidget);
  });

  testWidgets('profile, addresses, settings, help, privacy and terms navigate', (
    tester,
  ) async {
    await pump(tester, AuthStatus.authenticated);

    Future<void> expectOpens(String key, String destination) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      expect(find.text(destination), findsOneWidget, reason: '$key target');
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    await expectOpens('accountProfileTile', 'ProfilePage');
    await expectOpens('accountAddressesTile', 'AddressesPage');
    await expectOpens('accountSettingsTile', 'SettingsPage');
    await expectOpens('accountHelpTile', 'HelpPage');
    await expectOpens('accountPrivacyTile', 'PrivacyPage');
    await expectOpens('accountTermsTile', 'TermsPage');
  });

  testWidgets('saved products, shops and history each open their own tab', (
    tester,
  ) async {
    await pump(tester, AuthStatus.authenticated);

    // The deep link must carry the tab, otherwise every entry would dump
    // the customer onto the default "Saved Products" tab.
    await tester.tap(find.byKey(const Key('accountSavedProductsTile')));
    await tester.pumpAndSettle();
    expect(find.text('SavedPage:products'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('accountSavedShopsTile')));
    await tester.pumpAndSettle();
    expect(find.text('SavedPage:shops'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('accountSearchHistoryTile')));
    await tester.pumpAndSettle();
    expect(find.text('SavedPage:search'), findsOneWidget);
  });

  testWidgets('notifications entry opens the alerts list', (tester) async {
    await pump(tester, AuthStatus.authenticated);

    await tester.tap(find.byKey(const Key('accountNotificationsTile')));
    await tester.pumpAndSettle();

    expect(find.text('NotificationsPage'), findsOneWidget);
  });

  testWidgets('logout is confirmed before it runs', (tester) async {
    final auth = _StubAuthController(AuthStatus.authenticated);
    await pump(
      tester,
      AuthStatus.authenticated,
      authOverride: auth,
    );

    await tester.tap(find.byKey(const Key('accountLogoutTile')));
    await tester.pumpAndSettle();
    // Cancelling must not sign the customer out.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(auth.logoutCalled, isFalse);

    await tester.tap(find.byKey(const Key('accountLogoutTile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmAccountLogout')));
    await tester.pumpAndSettle();
    expect(auth.logoutCalled, isTrue);
  });

  testWidgets('guests see an exit-guest action, not a log out', (tester) async {
    await pump(tester, AuthStatus.guest);

    expect(find.text('Exit guest mode'), findsOneWidget);
    expect(find.text('Log out'), findsNothing);
  });

  testWidgets('a failed profile load still renders the whole account menu', (
    tester,
  ) async {
    await pump(
      tester,
      AuthStatus.authenticated,
      profileRepository: _FailingProfileRepository(),
    );

    // The summary degrades to a neutral label, but every row still works.
    expect(find.text('Your account'), findsOneWidget);
    expect(find.byKey(const Key('accountSettingsTile')), findsOneWidget);
    expect(find.byKey(const Key('accountLogoutTile')), findsOneWidget);
  });

  testWidgets('unread notifications are surfaced as a badge on the entry', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => _StubAuthController(AuthStatus.authenticated),
        ),
        profileRepositoryProvider.overrideWithValue(
          MockProfileRepository(delay: Duration.zero),
        ),
        notificationsRepositoryProvider.overrideWithValue(
          MockNotificationRepository(delay: Duration.zero),
        ),
      ],
    );
    addTearDown(container.dispose);
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

    // The mock seeds 4 unread items, so the account entry must show a count.
    expect(container.read(unreadCountProvider), 4);
    expect(find.text('4'), findsOneWidget);

    // Once everything is read the badge disappears rather than showing "0".
    await container
        .read(notificationsControllerProvider.notifier)
        .markAllAsRead();
    await tester.pumpAndSettle();
    expect(find.text('0'), findsNothing);
  });

  group('SavedItemsTab', () {
    test('resolves every deep-link name', () {
      expect(SavedItemsTab.fromQuery('products'), SavedItemsTab.products);
      expect(SavedItemsTab.fromQuery('shops'), SavedItemsTab.shops);
      expect(SavedItemsTab.fromQuery('search'), SavedItemsTab.search);
      expect(SavedItemsTab.fromQuery('viewed'), SavedItemsTab.viewed);
      expect(SavedItemsTab.fromQuery('viewedShops'), SavedItemsTab.viewedShops);
    });

    test('unknown or missing values fall back to Saved Products', () {
      // A hand-edited URL must never open an undefined tab.
      expect(SavedItemsTab.fromQuery('nonsense'), SavedItemsTab.products);
      expect(SavedItemsTab.fromQuery(null), SavedItemsTab.products);
      expect(SavedItemsTab.fromQuery(''), SavedItemsTab.products);
    });

    test('each tab has a distinct index inside the 5-tab controller', () {
      // `tabIndex`, not `index`: every Dart enum already declares a built-in
      // `index` getter, so the enum exposes its TabBar position under a
      // different name precisely to avoid the collision.
      final indices = SavedItemsTab.values.map((t) => t.tabIndex).toSet();
      expect(indices.length, SavedItemsTab.values.length);
      expect(indices.every((i) => i >= 0 && i < 5), isTrue);
    });
  });
}

