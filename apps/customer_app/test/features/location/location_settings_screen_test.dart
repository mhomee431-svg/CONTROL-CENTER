import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal_app/core/storage/local_storage_driver.dart';
import 'package:hyperlocal_app/features/location/domain/address_book_repository.dart';
import 'package:hyperlocal_app/features/location/domain/models/location_permission_status.dart';
import 'package:hyperlocal_app/features/location/domain/models/saved_address.dart';
import 'package:hyperlocal_app/features/location/domain/models/user_location.dart';
import 'package:hyperlocal_app/features/location/presentation/controllers/location_controller.dart';
import 'package:hyperlocal_app/features/location/presentation/screens/location_settings_screen.dart';

/// Address book with scripted entries, so the "Default address" row can be
/// asserted without touching real storage.
class _FakeAddressBook implements AddressBookRepository {
  _FakeAddressBook(this._addresses);

  List<SavedAddress> _addresses;

  @override
  Future<List<SavedAddress>> getAddresses() async => List.of(_addresses);

  @override
  Future<List<SavedAddress>> addAddress({
    required String label,
    required UserLocation location,
  }) async {
    _addresses = [
      ..._addresses,
      SavedAddress.create(
        id: 'a${_addresses.length}',
        label: label,
        location: location,
      ),
    ];
    return getAddresses();
  }

  @override
  Future<List<SavedAddress>> updateAddress({
    required String id,
    required String label,
    required UserLocation location,
  }) async => getAddresses();

  @override
  Future<List<SavedAddress>> removeAddress(String id) async {
    _addresses = _addresses.where((a) => a.id != id).toList();
    return getAddresses();
  }

  @override
  Future<List<SavedAddress>> setDefaultAddress(String id) async {
    _addresses = [
      for (final a in _addresses)
        a.id == id ? a.select() : a.copyWith(isSelected: false),
    ];
    return getAddresses();
  }
}

UserLocation _homeLocation() => UserLocation(
  latitude: 25.5941,
  longitude: 85.1376,
  address: '123 MG Road',
  city: 'Patna',
  accuracyMeters: 20,
  isSelected: true,
);

SavedAddress _homeAddress() =>
    SavedAddress.create(id: 'home', label: 'Home', location: _homeLocation());

/// Drives the location controller into a specific state.
void _setPermission(
  ProviderContainer container,
  LocationPermissionStatus permission, {
  UserLocation? location,
}) {
  container
      .read(locationControllerProvider.notifier)
      .debugSetState(
        LocationState(
          status: location == null
              ? LocationStatus.initial
              : LocationStatus.success,
          location: location,
          permissionStatus: permission,
        ),
      );
}

GoRouter _router() {
  return GoRouter(
    initialLocation: '/location-settings',
    routes: [
      GoRoute(
        path: '/location-settings',
        builder: (_, _) => const LocationSettingsScreen(),
      ),
      GoRoute(
        path: '/profile/addresses',
        builder: (_, _) => Scaffold(appBar: AppBar(), body: Text('AddressesPage')),
      ),
      GoRoute(
        path: '/map-picker',
        builder: (_, _) => Scaffold(appBar: AppBar(), body: Text('MapPickerPage')),
      ),
    ],
  );
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  List<SavedAddress>? addresses,
}) async {
  tester.view.physicalSize = const Size(1080, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      localStorageDriverProvider.overrideWithValue(InMemoryStorageDriver()),
      addressBookRepositoryProvider.overrideWithValue(
        _FakeAddressBook(addresses ?? const []),
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
  testWidgets('shows current location, default address and permission', (
    tester,
  ) async {
    await _pump(tester);

    // The three "show" items from the specification.
    expect(find.text('CURRENT LOCATION'), findsOneWidget);
    expect(find.text('DEFAULT ADDRESS'), findsOneWidget);
    expect(find.text('LOCATION PERMISSION'), findsOneWidget);
    expect(find.byKey(const Key('locationPermissionTile')), findsOneWidget);
  });

  testWidgets('offers use-current-location and manage-addresses', (
    tester,
  ) async {
    await _pump(tester);

    // The two "provide" actions from the specification.
    expect(find.byKey(const Key('locationUseCurrentButton')), findsOneWidget);
    expect(find.byKey(const Key('locationManageAddressesTile')), findsOneWidget);
    expect(find.text('Pick on map'), findsOneWidget);
  });

  testWidgets('an unset location explains what to do next', (tester) async {
    await _pump(tester);

    expect(find.text('No location set yet'), findsOneWidget);
    expect(find.text('No default address set'), findsOneWidget);
  });

  testWidgets('the default address is shown once one exists', (tester) async {
    await _pump(tester, addresses: [_homeAddress().select()]);

    expect(find.textContaining('Home'), findsOneWidget);
    expect(find.textContaining('123 MG Road'), findsOneWidget);
    expect(find.text('No default address set'), findsNothing);
  });

  testWidgets('the address count is reported, singular and plural', (
    tester,
  ) async {
    await _pump(tester, addresses: [_homeAddress()]);
    expect(find.text('1 saved address'), findsOneWidget);

    await _pump(
      tester,
      addresses: [
        _homeAddress(),
        SavedAddress.create(
          id: 'work',
          label: 'Work',
          location: _homeLocation(),
        ),
      ],
    );
    expect(find.text('2 saved addresses'), findsOneWidget);
  });

  testWidgets('a blocked permission offers system settings, not Allow', (
    tester,
  ) async {
    // Permanently denied is a dead end for in-app prompts: the OS will not
    // show a dialog again. Offering "Allow" here would be a button that lies.
    final container = await _pump(tester);
    _setPermission(
      container,
      LocationPermissionStatus.permanentlyDenied,
    );
    await tester.pumpAndSettle();

    expect(find.text('Blocked'), findsOneWidget);
    expect(
      find.byKey(const Key('permissionOpenSettingsButton')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('permissionAllowButton')), findsNothing);
  });

  testWidgets('a denied permission offers Allow', (tester) async {
    final container = await _pump(tester);
    _setPermission(container, LocationPermissionStatus.denied);
    await tester.pumpAndSettle();

    expect(find.text('Not allowed'), findsOneWidget);
    expect(find.byKey(const Key('permissionAllowButton')), findsOneWidget);
  });

  testWidgets('a granted permission shows no corrective action', (
    tester,
  ) async {
    final container = await _pump(tester);
    _setPermission(
      container,
      LocationPermissionStatus.granted,
      location: _homeLocation(),
    );
    await tester.pumpAndSettle();

    expect(find.text('Allowed'), findsOneWidget);
    expect(find.byKey(const Key('permissionAllowButton')), findsNothing);
    expect(find.byKey(const Key('permissionOpenSettingsButton')), findsNothing);
    // The resolved location is surfaced, not just the status.
    expect(find.textContaining('123 MG Road'), findsOneWidget);
  });

  testWidgets('accuracy is reported honestly, never overstated', (
    tester,
  ) async {
    final container = await _pump(tester);
    _setPermission(
      container,
      LocationPermissionStatus.granted,
      location: _homeLocation(), // accuracyMeters: 20
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Accurate to ~20 m'), findsOneWidget);
  });

  testWidgets('manage addresses navigates to the address book', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('locationManageAddressesTile')));
    await tester.pumpAndSettle();

    expect(find.text('AddressesPage'), findsOneWidget);
  });
}
