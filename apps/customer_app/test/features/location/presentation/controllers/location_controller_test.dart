import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyperlocal_app/core/storage/secure_storage_service.dart';
import 'package:hyperlocal_app/features/location/domain/location_repository.dart';
import 'package:hyperlocal_app/features/location/domain/models/location_exception.dart';
import 'package:hyperlocal_app/features/location/domain/models/location_permission_status.dart';
import 'package:hyperlocal_app/features/location/domain/models/saved_address.dart';
import 'package:hyperlocal_app/features/location/domain/models/user_location.dart';
import 'package:hyperlocal_app/features/location/presentation/controllers/location_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'location_controller_test.mocks.dart';

@GenerateMocks([LocationRepository, SecureStorageService])
void main() {
  late MockLocationRepository mockRepository;
  late MockSecureStorageService mockStorage;
  late ProviderContainer container;
  late LocationController controller;

  const testLocation = UserLocation(
    latitude: 25.5941,
    longitude: 85.1376,
    address: 'Patna Center',
    city: 'Patna',
    state: 'Bihar',
    pincode: '800001',
    label: 'Patna',
  );

  setUp(() {
    mockRepository = MockLocationRepository();
    mockStorage = MockSecureStorageService();

    // Stateful in-memory storage behavior
    final store = <String, String>{};
    when(mockStorage.write(key: anyNamed('key'), value: anyNamed('value')))
        .thenAnswer((invocation) async {
      final key = invocation.namedArguments[#key] as String;
      final value = invocation.namedArguments[#value] as String;
      store[key] = value;
    });
    when(mockStorage.read(key: anyNamed('key')))
        .thenAnswer((invocation) async {
      final key = invocation.namedArguments[#key] as String;
      return store[key];
    });
    when(mockStorage.delete(key: anyNamed('key')))
        .thenAnswer((invocation) async {
      final key = invocation.namedArguments[#key] as String;
      store.remove(key);
    });

    container = ProviderContainer(
      overrides: [
        locationRepositoryProvider.overrideWithValue(mockRepository),
        secureStorageProvider.overrideWithValue(mockStorage),
      ],
    );

    controller = container.read(locationControllerProvider.notifier);
  });

  tearDown(() {
    container.dispose();
  });

  test('Initial state should be LocationStatus.initial', () {
    expect(container.read(locationControllerProvider).status, LocationStatus.initial);
    expect(container.read(locationControllerProvider).location, isNull);
  });

  test('loadSavedLocation with stored location sets success state', () async {
    await mockStorage.write(key: 'user_saved_location', value: jsonEncode(testLocation.toJson()));

    await controller.loadSavedLocation();

    final state = container.read(locationControllerProvider);
    expect(state.status, LocationStatus.success);
    expect(state.location, testLocation);
  });

  test('loadSavedLocation with no stored location keeps initial state', () async {
    await controller.loadSavedLocation();

    expect(container.read(locationControllerProvider).status, LocationStatus.initial);
    expect(container.read(locationControllerProvider).location, isNull);
  });

  test('loadSavedLocation with corrupt data keeps initial state', () async {
    await mockStorage.write(key: 'user_saved_location', value: 'not-json');

    await controller.loadSavedLocation();

    expect(container.read(locationControllerProvider).status, LocationStatus.initial);
  });

  test('fetchCurrentLocation with GPS off sets serviceDisabled state', () async {
    when(mockRepository.isLocationServiceEnabled()).thenAnswer((_) async => false);

    await controller.fetchCurrentLocation();

    final state = container.read(locationControllerProvider);
    expect(state.status, LocationStatus.serviceDisabled);
    expect(state.errorMessage, contains('GPS'));
  });

  test('fetchCurrentLocation with denied permission sets permissionDenied state', () async {
    when(mockRepository.isLocationServiceEnabled()).thenAnswer((_) async => true);
    when(mockRepository.requestPermission())
        .thenAnswer((_) async => LocationPermissionStatus.denied);

    await controller.fetchCurrentLocation();

    final state = container.read(locationControllerProvider);
    expect(state.status, LocationStatus.permissionDenied);
    expect(state.errorMessage, contains('permission'));
  });

  test('fetchCurrentLocation with permanently denied permission sets permissionPermanentlyDenied state', () async {
    when(mockRepository.isLocationServiceEnabled()).thenAnswer((_) async => true);
    when(mockRepository.requestPermission())
        .thenAnswer((_) async => LocationPermissionStatus.permanentlyDenied);

    await controller.fetchCurrentLocation();

    final state = container.read(locationControllerProvider);
    expect(state.status, LocationStatus.permissionPermanentlyDenied);
    expect(state.errorMessage, contains('permanently denied'));
  });

  test('fetchCurrentLocation success saves location and sets success state', () async {
    when(mockRepository.isLocationServiceEnabled()).thenAnswer((_) async => true);
    when(mockRepository.requestPermission())
        .thenAnswer((_) async => LocationPermissionStatus.granted);
    when(mockRepository.getCurrentLocation()).thenAnswer((_) async => testLocation);

    await controller.fetchCurrentLocation();

    final state = container.read(locationControllerProvider);
    expect(state.status, LocationStatus.success);
    expect(state.location, testLocation);
    final saved = await mockStorage.read(key: 'user_saved_location');
    expect(saved, jsonEncode(testLocation.toJson()));
  });

  test('fetchCurrentLocation with LocationException sets error state', () async {
    when(mockRepository.isLocationServiceEnabled()).thenAnswer((_) async => true);
    when(mockRepository.requestPermission())
        .thenAnswer((_) async => LocationPermissionStatus.granted);
    when(mockRepository.getCurrentLocation())
        .thenThrow(const LocationException(LocationErrorType.locationUnavailable, 'No GPS fix'));

    await controller.fetchCurrentLocation();

    final state = container.read(locationControllerProvider);
    expect(state.status, LocationStatus.error);
    expect(state.errorMessage, contains('No GPS fix'));
  });

  test('fetchCurrentLocation with generic error sets error state', () async {
    when(mockRepository.isLocationServiceEnabled()).thenAnswer((_) async => true);
    when(mockRepository.requestPermission())
        .thenAnswer((_) async => LocationPermissionStatus.granted);
    when(mockRepository.getCurrentLocation()).thenThrow(Exception('GPS failure'));

    await controller.fetchCurrentLocation();

    final state = container.read(locationControllerProvider);
    expect(state.status, LocationStatus.error);
    expect(state.errorMessage, contains('GPS failure'));
  });

  test('fetchCurrentLocation throttles repeated calls within interval', () async {
    // First call succeeds
    when(mockRepository.isLocationServiceEnabled()).thenAnswer((_) async => true);
    when(mockRepository.requestPermission())
        .thenAnswer((_) async => LocationPermissionStatus.granted);
    when(mockRepository.getCurrentLocation()).thenAnswer((_) async => testLocation);

    await controller.fetchCurrentLocation();

    // Second call within 5 min should use saved location, not GPS
    await mockStorage.write(
      key: 'last_location_fetch_ms',
      value: DateTime.now().millisecondsSinceEpoch.toString(),
    );

    await controller.fetchCurrentLocation();

    final state = container.read(locationControllerProvider);
    expect(state.status, LocationStatus.success);
    expect(state.location, testLocation);
    // GPS should not be called again
    verify(mockRepository.getCurrentLocation()).called(1);
  });

  test('refreshLocation bypasses throttle', () async {
    // First call succeeds
    when(mockRepository.isLocationServiceEnabled()).thenAnswer((_) async => true);
    when(mockRepository.requestPermission())
        .thenAnswer((_) async => LocationPermissionStatus.granted);
    when(mockRepository.getCurrentLocation()).thenAnswer((_) async => testLocation);

    await controller.fetchCurrentLocation();

    // Second call with force=true should hit GPS again
    await mockStorage.write(
      key: 'last_location_fetch_ms',
      value: DateTime.now().millisecondsSinceEpoch.toString(),
    );

    await controller.refreshLocation();

    verify(mockRepository.getCurrentLocation()).called(2);
  });

  test('retry re-attempts a failed location request', () async {
    when(mockRepository.isLocationServiceEnabled()).thenAnswer((_) async => true);
    when(mockRepository.requestPermission())
        .thenAnswer((_) async => LocationPermissionStatus.granted);
    when(mockRepository.getCurrentLocation())
        .thenThrow(const LocationException(LocationErrorType.locationUnavailable, 'No fix'));

    await controller.fetchCurrentLocation();
    expect(container.read(locationControllerProvider).status, LocationStatus.error);

    // Now GPS works
    when(mockRepository.getCurrentLocation()).thenAnswer((_) async => testLocation);

    await controller.retry();

    final state = container.read(locationControllerProvider);
    expect(state.status, LocationStatus.success);
    expect(state.location, testLocation);
  });

  test('setManualLocation saves location and sets success state', () async {
    const manualLocation = UserLocation(
      latitude: 24.7914,
      longitude: 85.0002,
      address: 'Gaya Center',
      city: 'Gaya',
      state: 'Bihar',
      pincode: '823001',
      label: 'Gaya',
      isManual: true,
    );

    await controller.setManualLocation(manualLocation);

    final state = container.read(locationControllerProvider);
    expect(state.status, LocationStatus.success);
    expect(state.location!.latitude, manualLocation.latitude);
    expect(state.location!.longitude, manualLocation.longitude);
    expect(state.location!.city, manualLocation.city);
    expect(state.location!.isSelected, isTrue);
    final saved = await mockStorage.read(key: 'user_saved_location');
    expect(saved, isNotNull);
  });

  test('saveAddress persists a new saved address', () async {
    await controller.saveAddress(label: 'Home', location: testLocation);

    final addresses = await controller.loadSavedAddresses();
    expect(addresses.length, 1);
    expect(addresses.first.label, 'Home');
    expect(addresses.first.location, testLocation);
  });

  test('selectSavedAddress sets it as current location', () async {
    final address = SavedAddress.create(
      id: 'addr-1',
      label: 'Home',
      location: testLocation,
      savedAt: DateTime.now(),
    );

    await controller.selectSavedAddress(address);

    final state = container.read(locationControllerProvider);
    expect(state.status, LocationStatus.success);
    expect(state.location!.latitude, testLocation.latitude);
    expect(state.location!.longitude, testLocation.longitude);
    expect(state.location!.isSelected, isTrue);
  });

  test('removeSavedAddress removes by ID', () async {
    final address = SavedAddress.create(
      id: 'addr-1',
      label: 'Home',
      location: testLocation,
      savedAt: DateTime.now(),
    );
    await mockStorage.write(
      key: 'user_saved_addresses',
      value: jsonEncode([address.toJson()]),
    );

    await controller.removeSavedAddress('addr-1');

    final addresses = await controller.loadSavedAddresses();
    expect(addresses.length, 0);
  });
}