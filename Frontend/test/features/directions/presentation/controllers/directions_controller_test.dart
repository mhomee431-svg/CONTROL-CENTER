import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:hyperlocal_customer_app/features/directions/domain/location_service.dart';
import 'package:hyperlocal_customer_app/features/directions/domain/models/location_models.dart';
import 'package:hyperlocal_customer_app/features/directions/presentation/controllers/directions_controller.dart';

import 'directions_controller_test.mocks.dart';

@GenerateMocks([LocationService])
void main() {
  group('DirectionsController', () {
    late MockLocationService mockLocationService;
    late ProviderContainer container;
    late List<ProviderSubscription> subscriptions;

    const shopId = 'shop_1';
    const userLocation = Coordinates(28.7041, 77.1025);

    setUp(() {
      mockLocationService = MockLocationService();
      subscriptions = [];
      container = ProviderContainer(
        overrides: [
          locationServiceProvider.overrideWithValue(mockLocationService),
        ],
      );
    });

    tearDown(() {
      for (final sub in subscriptions) {
        sub.close();
      }
      container.dispose();
    });

    /// Keeps the autoDispose provider alive by subscribing to it.
    DirectionsState readState() {
      final sub = container.listen(
        directionsControllerProvider(shopId),
        (_, _) {},
        fireImmediately: true,
      );
      subscriptions.add(sub);
      return sub.read();
    }

    Future<DirectionsState> waitForState() async {
      readState(); // Keep provider alive
      await Future.delayed(const Duration(milliseconds: 100));
      return container.read(directionsControllerProvider(shopId));
    }

    test('initial state is loading', () {
      when(mockLocationService.isGpsEnabled()).thenAnswer((_) async => true);
      when(mockLocationService.requestPermission()).thenAnswer((_) async => true);
      when(mockLocationService.getCurrentLocation())
          .thenAnswer((_) async => userLocation);
      when(mockLocationService.calculateDistance(any, any)).thenReturn(1.5);

      final state = readState();

      expect(state.isLoading, true);
      expect(state.error, isNull);
      expect(state.userLocation, isNull);
    });

    test('handles No GPS error properly', () async {
      when(mockLocationService.isGpsEnabled()).thenAnswer((_) async => false);

      final state = await waitForState();

      expect(state.isLoading, false);
      expect(state.error, LocationErrorType.noGps);
      expect(state.userLocation, isNull);
      expect(state.shopLocation, isNull);
      expect(state.distanceInKm, isNull);

      verify(mockLocationService.isGpsEnabled());
      verifyNever(mockLocationService.requestPermission());
      verifyNever(mockLocationService.getCurrentLocation());
    });

    test('handles Permission Denied error properly', () async {
      when(mockLocationService.isGpsEnabled()).thenAnswer((_) async => true);
      when(mockLocationService.requestPermission()).thenAnswer((_) async => false);

      final state = await waitForState();

      expect(state.isLoading, false);
      expect(state.error, LocationErrorType.permissionDenied);
      expect(state.userLocation, isNull);
      expect(state.shopLocation, isNull);
      expect(state.distanceInKm, isNull);

      verify(mockLocationService.isGpsEnabled());
      verify(mockLocationService.requestPermission());
      verifyNever(mockLocationService.getCurrentLocation());
    });

    test('successfully loads route with distance', () async {
      when(mockLocationService.isGpsEnabled()).thenAnswer((_) async => true);
      when(mockLocationService.requestPermission()).thenAnswer((_) async => true);
      when(mockLocationService.getCurrentLocation())
          .thenAnswer((_) async => userLocation);
      when(mockLocationService.calculateDistance(any, any)).thenReturn(1.2345);

      final state = await waitForState();

      expect(state.isLoading, false);
      expect(state.error, isNull);
      expect(state.userLocation, userLocation);
      expect(state.shopLocation, isNotNull);
      expect(state.distanceInKm, 1.23); // Rounded to 2 decimal places

      verify(mockLocationService.isGpsEnabled());
      verify(mockLocationService.requestPermission());
      verify(mockLocationService.getCurrentLocation());
      verify(mockLocationService.calculateDistance(any, any));
    });

    test('retry re-initializes the route after no GPS', () async {
      when(mockLocationService.isGpsEnabled()).thenAnswer((_) async => false);

      var state = await waitForState();
      expect(state.error, LocationErrorType.noGps);

      // Now GPS becomes enabled and retry succeeds
      when(mockLocationService.isGpsEnabled()).thenAnswer((_) async => true);
      when(mockLocationService.requestPermission()).thenAnswer((_) async => true);
      when(mockLocationService.getCurrentLocation())
          .thenAnswer((_) async => userLocation);
      when(mockLocationService.calculateDistance(any, any)).thenReturn(1.5);

      await container.read(directionsControllerProvider(shopId).notifier).retry();
      await Future.delayed(const Duration(milliseconds: 100));

      state = container.read(directionsControllerProvider(shopId));

      expect(state.isLoading, false);
      expect(state.error, isNull);
      expect(state.distanceInKm, isNotNull);
    });

    test('handles LocationException gracefully', () async {
      when(mockLocationService.isGpsEnabled()).thenAnswer((_) async => true);
      when(mockLocationService.requestPermission()).thenAnswer((_) async => true);
      when(mockLocationService.getCurrentLocation())
          .thenThrow(const LocationException(
        LocationErrorType.networkFailure,
        'Network failure',
      ));

      final state = await waitForState();

      expect(state.isLoading, false);
      expect(state.error, LocationErrorType.networkFailure);
      expect(state.userLocation, isNull);
    });

    test('launchExternalMaps calls openExternalNavigation with shop location', () async {
      when(mockLocationService.isGpsEnabled()).thenAnswer((_) async => true);
      when(mockLocationService.requestPermission()).thenAnswer((_) async => true);
      when(mockLocationService.getCurrentLocation())
          .thenAnswer((_) async => userLocation);
      when(mockLocationService.calculateDistance(any, any)).thenReturn(1.5);

      await waitForState();

      when(mockLocationService.openExternalNavigation(any, any))
          .thenAnswer((_) async {});

      final controller = container.read(directionsControllerProvider(shopId).notifier);
      await controller.launchExternalMaps('Test Shop');

      verify(mockLocationService.openExternalNavigation(
        argThat(isA<Coordinates>()),
        'Test Shop',
      ));
    });
  });
}