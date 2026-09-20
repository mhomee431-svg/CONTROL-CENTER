import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:hyperlocal_app/features/directions/domain/location_service.dart';
import 'package:hyperlocal_app/features/directions/domain/models/location_models.dart';
import 'package:hyperlocal_app/features/directions/presentation/controllers/directions_controller.dart';
import 'package:hyperlocal_app/features/shop_details/domain/shop_details_repository.dart';
import 'package:hyperlocal_app/features/shop_details/domain/models/shop_details_models.dart';

import 'directions_controller_test.mocks.dart';

@GenerateMocks([LocationService, ShopDetailsRepository])
void main() {
  group('DirectionsController', () {
    late MockLocationService mockLocationService;
    late MockShopDetailsRepository mockShopRepo;
    late ProviderContainer container;
    late List<ProviderSubscription> subscriptions;

    const shopId = 'shop_1';
    const userLocation = Coordinates(28.7041, 77.1025);
    const shopLocation = Coordinates(28.7150, 77.1150);

    ShopProfile buildShopProfile({bool open = true, bool hasCoords = true}) {
      return ShopProfile(
        id: shopId,
        name: 'Test Shop',
        imageUrl: '',
        rating: 4.5,
        reviewCount: 10,
        address: 'Test Address',
        distanceInKm: 1.2,
        openingHours: 'Mon-Sun, 10:00 AM - 9:00 PM',
        isOpenNow: open,
        phone: '+911234567890',
        about: 'About',
        lastInventoryUpdate: DateTime.now(),
        activeOffers: const [],
        availableProducts: const [],
        isSaved: false,
        categories: const ['Hardware'],
        isVerified: true,
        latitude: hasCoords ? shopLocation.latitude : 0,
        longitude: hasCoords ? shopLocation.longitude : 0,
      );
    }

    setUp(() {
      mockLocationService = MockLocationService();
      mockShopRepo = MockShopDetailsRepository();
      subscriptions = [];
      container = ProviderContainer(
        overrides: [
          locationServiceProvider.overrideWithValue(mockLocationService),
          shopDetailsRepositoryProvider.overrideWithValue(mockShopRepo),
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
      when(mockShopRepo.getShopProfile(shopId))
          .thenAnswer((_) async => buildShopProfile());

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
      verifyNever(mockShopRepo.getShopProfile(shopId));
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
      verifyNever(mockShopRepo.getShopProfile(shopId));
    });

    test('successfully loads route with distance', () async {
      when(mockLocationService.isGpsEnabled()).thenAnswer((_) async => true);
      when(mockLocationService.requestPermission()).thenAnswer((_) async => true);
      when(mockLocationService.getCurrentLocation())
          .thenAnswer((_) async => userLocation);
      when(mockLocationService.calculateDistance(any, any)).thenReturn(1.2345);
      when(mockShopRepo.getShopProfile(shopId))
          .thenAnswer((_) async => buildShopProfile());

      final state = await waitForState();

      expect(state.isLoading, false);
      expect(state.error, isNull);
      expect(state.userLocation, userLocation);
      expect(state.shopLocation, shopLocation);
      expect(state.distanceInKm, 1.23); // Rounded to 2 decimal places
      expect(state.isShopClosed, false);

      verify(mockLocationService.isGpsEnabled());
      verify(mockLocationService.requestPermission());
      verify(mockLocationService.getCurrentLocation());
      verify(mockLocationService.calculateDistance(any, any));
      verify(mockShopRepo.getShopProfile(shopId));
    });

    test('marks shop as closed when shop is not open', () async {
      when(mockLocationService.isGpsEnabled()).thenAnswer((_) async => true);
      when(mockLocationService.requestPermission()).thenAnswer((_) async => true);
      when(mockLocationService.getCurrentLocation())
          .thenAnswer((_) async => userLocation);
      when(mockLocationService.calculateDistance(any, any)).thenReturn(1.5);
      when(mockShopRepo.getShopProfile(shopId))
          .thenAnswer((_) async => buildShopProfile(open: false));

      final state = await waitForState();

      expect(state.isLoading, false);
      expect(state.error, isNull);
      expect(state.isShopClosed, true);
    });

    test('handles invalid shop coordinates', () async {
      when(mockLocationService.isGpsEnabled()).thenAnswer((_) async => true);
      when(mockLocationService.requestPermission()).thenAnswer((_) async => true);
      when(mockLocationService.getCurrentLocation())
          .thenAnswer((_) async => userLocation);
      when(mockShopRepo.getShopProfile(shopId))
          .thenAnswer((_) async => buildShopProfile(hasCoords: false));

      final state = await waitForState();

      expect(state.isLoading, false);
      expect(state.error, LocationErrorType.invalidCoordinates);
      expect(state.shopLocation, isNull);
      expect(state.distanceInKm, isNull);
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
      when(mockShopRepo.getShopProfile(shopId))
          .thenAnswer((_) async => buildShopProfile());

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
      when(mockShopRepo.getShopProfile(shopId))
          .thenAnswer((_) async => buildShopProfile());

      final state = await waitForState();

      expect(state.isLoading, false);
      expect(state.error, LocationErrorType.networkFailure);
      expect(state.userLocation, isNull);
    });

    test('handles shop repository network failure', () async {
      when(mockLocationService.isGpsEnabled()).thenAnswer((_) async => true);
      when(mockLocationService.requestPermission()).thenAnswer((_) async => true);
      when(mockShopRepo.getShopProfile(shopId))
          .thenThrow(Exception('Network failure'));

      final state = await waitForState();

      expect(state.isLoading, false);
      expect(state.error, LocationErrorType.networkFailure);
      expect(state.shopLocation, isNull);
    });

    test('launchExternalMaps calls openExternalNavigation with shop location', () async {
      when(mockLocationService.isGpsEnabled()).thenAnswer((_) async => true);
      when(mockLocationService.requestPermission()).thenAnswer((_) async => true);
      when(mockLocationService.getCurrentLocation())
          .thenAnswer((_) async => userLocation);
      when(mockLocationService.calculateDistance(any, any)).thenReturn(1.5);
      when(mockShopRepo.getShopProfile(shopId))
          .thenAnswer((_) async => buildShopProfile());

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