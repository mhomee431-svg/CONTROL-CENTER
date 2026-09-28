import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal_app/core/storage/secure_storage_service.dart';
import 'package:hyperlocal_app/features/auth/presentation/screens/welcome_screen.dart';
import 'package:hyperlocal_app/features/location/domain/location_repository.dart';
import 'package:hyperlocal_app/features/location/domain/models/location_permission_status.dart';
import 'package:hyperlocal_app/features/location/domain/models/user_location.dart';

/// Minimal in-memory secure storage — the location controller only writes the
/// captured position and the fetch timestamp.
class _FakeSecureStorage implements SecureStorageService {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Scriptable location provider so each test chooses its own outcome.
class _FakeLocationRepository implements LocationRepository {
  _FakeLocationRepository({
    this.serviceEnabled = true,
    this.permission = LocationPermissionStatus.granted,
    this.location = const UserLocation(
      latitude: 12.9716,
      longitude: 77.5946,
      address: 'MG Road, Bengaluru',
      city: 'Bengaluru',
    ),
  });

  bool serviceEnabled;
  LocationPermissionStatus permission;
  UserLocation location;
  int requestPermissionCalls = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermissionStatus> checkPermission() async => permission;

  @override
  Future<LocationPermissionStatus> requestPermission() async {
    requestPermissionCalls++;
    return permission;
  }

  @override
  Future<UserLocation> getCurrentLocation() async => location;

  @override
  Future<UserLocation?> getLastKnownLocation() async => null;

  @override
  Future<void> openLocationSettings() async {}

  @override
  Future<List<UserLocation>> searchManualLocations(String query) async => [];
}

void main() {
  Future<void> pumpWelcome(
    WidgetTester tester, {
    _FakeLocationRepository? repository,
  }) async {
    final router = GoRouter(
      initialLocation: '/welcome',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('LOGIN')),
        ),
        GoRoute(
          path: '/select-location',
          builder: (_, _) => const Scaffold(body: Text('SELECT_LOCATION')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationRepositoryProvider.overrideWithValue(
            repository ?? _FakeLocationRepository(),
          ),
          secureStorageProvider.overrideWithValue(_FakeSecureStorage()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the HyperLocal brand and the required copy', (
    WidgetTester tester,
  ) async {
    await pumpWelcome(tester);

    expect(find.text('HyperLocal'), findsOneWidget);
    expect(find.text('Find Products Nearby'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.text('Login / Continue'), findsOneWidget);
  });

  testWidgets('opening the screen never requests location permission', (
    WidgetTester tester,
  ) async {
    final repo = _FakeLocationRepository();
    await pumpWelcome(tester, repository: repo);

    await tester.pump(const Duration(milliseconds: 500));

    // The opt-in affordance is offered, but nothing was asked for.
    expect(find.byKey(const Key('detectLocationButton')), findsOneWidget);
    expect(repo.requestPermissionCalls, 0);
  });

  testWidgets('tapping detect resolves the location and shows it', (
    WidgetTester tester,
  ) async {
    final repo = _FakeLocationRepository();
    await pumpWelcome(tester, repository: repo);

    await tester.tap(find.byKey(const Key('detectLocationButton')));
    await tester.pumpAndSettle();

    expect(repo.requestPermissionCalls, 1);
    expect(find.text('Products near MG Road, Bengaluru'), findsOneWidget);
    // Pin becomes the "located" affordance and offers a refresh.
    expect(find.text('Update location'), findsOneWidget);
    expect(find.byKey(const Key('chooseAreaManuallyButton')), findsNothing);
  });

  testWidgets('a denied permission degrades gracefully and never blocks', (
    WidgetTester tester,
  ) async {
    final repo = _FakeLocationRepository(
      permission: LocationPermissionStatus.denied,
    );
    await pumpWelcome(tester, repository: repo);

    await tester.tap(find.byKey(const Key('detectLocationButton')));
    await tester.pumpAndSettle();

    expect(repo.requestPermissionCalls, 1);
    expect(find.byKey(const Key('detectLocationMessage')), findsOneWidget);
    // Manual fallback stays available so the customer is never stuck.
    expect(find.byKey(const Key('chooseAreaManuallyButton')), findsOneWidget);
    // Core CTAs still work.
    expect(find.text('Get Started'), findsOneWidget);
  });

  testWidgets('disabled location services explain the failure', (
    WidgetTester tester,
  ) async {
    final repo = _FakeLocationRepository(serviceEnabled: false);
    await pumpWelcome(tester, repository: repo);

    await tester.tap(find.byKey(const Key('detectLocationButton')));
    await tester.pumpAndSettle();

    // No permission was even requested because GPS is off.
    expect(repo.requestPermissionCalls, 0);
    expect(find.byKey(const Key('detectLocationMessage')), findsOneWidget);
    expect(find.byKey(const Key('chooseAreaManuallyButton')), findsOneWidget);
  });

  testWidgets('a fix with no readable label still reports a location', (
    WidgetTester tester,
  ) async {
    final repo = _FakeLocationRepository(
      location: const UserLocation(latitude: 12.9716, longitude: 77.5946),
    );
    await pumpWelcome(tester, repository: repo);

    await tester.tap(find.byKey(const Key('detectLocationButton')));
    await tester.pumpAndSettle();

    // Reverse geocoding can return nothing; fall back to a generic label.
    expect(find.text('Products near Current location'), findsOneWidget);
  });

  testWidgets('Choose area manually opens the location picker', (
    WidgetTester tester,
  ) async {
    await pumpWelcome(tester);

    await tester.tap(find.byKey(const Key('chooseAreaManuallyButton')));
    await tester.pumpAndSettle();

    expect(find.text('SELECT_LOCATION'), findsOneWidget);
  });

  testWidgets('Get Started goes to the home shell', (
    WidgetTester tester,
  ) async {
    await pumpWelcome(tester);

    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('Login / Continue opens the passwordless login screen', (
    WidgetTester tester,
  ) async {
    await pumpWelcome(tester);

    await tester.tap(find.text('Login / Continue'));
    await tester.pumpAndSettle();

    expect(find.text('LOGIN'), findsOneWidget);
  });
}
