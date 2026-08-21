import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyperlocal_customer_app/core/storage/secure_storage_service.dart';
import 'package:hyperlocal_customer_app/features/location/domain/location_repository.dart';
import 'package:hyperlocal_customer_app/features/location/domain/models/user_location.dart';
import 'package:hyperlocal_customer_app/features/location/presentation/controllers/location_controller.dart';
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
  );

  setUp(() {
    mockRepository = MockLocationRepository();
    mockStorage = MockSecureStorageService();

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
    final locationJson = jsonEncode(testLocation.toJson());
    when(mockStorage.read(key: 'user_saved_location')).thenAnswer((_) async => locationJson);

    await controller.loadSavedLocation();

    final state = container.read(locationControllerProvider);
    expect(state.status, LocationStatus.success);
    expect(state.location, testLocation);
  });

  test('loadSavedLocation with no stored location keeps initial state', () async {
    when(mockStorage.read(key: 'user_saved_location')).thenAnswer((_) async => null);

    await controller.loadSavedLocation();

    expect(container.read(locationControllerProvider).status, LocationStatus.initial);
    expect(container.read(locationControllerProvider).location, isNull);
  });

  test('fetchCurrentLocation with GPS off sets serviceDisabled state', () async {
    when(mockRepository.isLocationServiceEnabled()).thenAnswer((_) async => false);

    await controller.fetchCurrentLocation();

    final state = container.read(locationControllerProvider);
    expect(state.status, LocationStatus.serviceDisabled);
    expect(state.errorMessage, 'GPS is turned off');
  });

  test('fetchCurrentLocation with denied permission sets permissionDenied state', () async {
    when(mockRepository.isLocationServiceEnabled()).thenAnswer((_) async => true);
    when(mockRepository.requestPermission()).thenAnswer((_) async => false);

    await controller.fetchCurrentLocation();

    final state = container.read(locationControllerProvider);
    expect(state.status, LocationStatus.permissionDenied);
    expect(state.errorMessage, 'Location permission denied');
  });

  test('fetchCurrentLocation success saves location and sets success state', () async {
    when(mockRepository.isLocationServiceEnabled()).thenAnswer((_) async => true);
    when(mockRepository.requestPermission()).thenAnswer((_) async => true);
    when(mockRepository.getCurrentLocation()).thenAnswer((_) async => testLocation);
    when(mockStorage.write(key: 'user_saved_location', value: jsonEncode(testLocation.toJson())))
        .thenAnswer((_) async => {});

    await controller.fetchCurrentLocation();

    final state = container.read(locationControllerProvider);
    expect(state.status, LocationStatus.success);
    expect(state.location, testLocation);
    verify(mockStorage.write(key: 'user_saved_location', value: jsonEncode(testLocation.toJson()))).called(1);
  });

  test('fetchCurrentLocation with error sets error state', () async {
    when(mockRepository.isLocationServiceEnabled()).thenAnswer((_) async => true);
    when(mockRepository.requestPermission()).thenAnswer((_) async => true);
    when(mockRepository.getCurrentLocation()).thenThrow(Exception('GPS failure'));

    await controller.fetchCurrentLocation();

    final state = container.read(locationControllerProvider);
    expect(state.status, LocationStatus.error);
    expect(state.errorMessage, contains('GPS failure'));
  });

  test('setManualLocation saves location and sets success state', () async {
    const manualLocation = UserLocation(
      latitude: 24.7914,
      longitude: 85.0002,
      address: 'Gaya Center',
      city: 'Gaya',
      state: 'Bihar',
      pincode: '823001',
      isManual: true,
    );
    when(mockStorage.write(key: 'user_saved_location', value: jsonEncode(manualLocation.toJson())))
        .thenAnswer((_) async => {});

    await controller.setManualLocation(manualLocation);

    final state = container.read(locationControllerProvider);
    expect(state.status, LocationStatus.success);
    expect(state.location, manualLocation);
    verify(mockStorage.write(key: 'user_saved_location', value: jsonEncode(manualLocation.toJson()))).called(1);
  });
}