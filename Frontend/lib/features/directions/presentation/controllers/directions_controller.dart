import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/location_service.dart';
import '../../domain/models/location_models.dart';

class DirectionsState {
  final bool isLoading;
  final LocationErrorType? error;
  final Coordinates? userLocation;
  final Coordinates? shopLocation;
  final double? distanceInKm;

  const DirectionsState({
    this.isLoading = true,
    this.error,
    this.userLocation,
    this.shopLocation,
    this.distanceInKm,
  });
}

final directionsControllerProvider = NotifierProvider.autoDispose
    .family<DirectionsController, DirectionsState, String>(
  DirectionsController.new,
);

class DirectionsController extends Notifier<DirectionsState> {
  DirectionsController(this.shopId);

  final String shopId;

  @override
  DirectionsState build() {
    _initRoute();
    return const DirectionsState(isLoading: true);
  }

  Future<void> _initRoute() async {
    state = const DirectionsState(isLoading: true);
    try {
      final locationService = ref.read(locationServiceProvider);

      final hasGps = await locationService.isGpsEnabled();
      if (!ref.mounted) return;
      if (!hasGps) {
        state = const DirectionsState(
          isLoading: false,
          error: LocationErrorType.noGps,
        );
        return;
      }

      final hasPermission = await locationService.requestPermission();
      if (!ref.mounted) return;
      if (!hasPermission) {
        state = const DirectionsState(
          isLoading: false,
          error: LocationErrorType.permissionDenied,
        );
        return;
      }

      final userLoc = await locationService.getCurrentLocation();
      if (!ref.mounted) return;

      // In a real app, fetch this via a ShopRepository.
      // Mocking shop coordinates for now.
      const shopLoc = Coordinates(28.7150, 77.1150);

      if (shopLoc.latitude == 0 && shopLoc.longitude == 0) {
        throw const LocationException(
          LocationErrorType.invalidCoordinates,
          'Invalid shop coordinates',
        );
      }

      final distance = locationService.calculateDistance(userLoc, shopLoc);

      state = DirectionsState(
        isLoading: false,
        userLocation: userLoc,
        shopLocation: shopLoc,
        distanceInKm: double.parse(distance.toStringAsFixed(2)),
      );
    } on LocationException catch (e) {
      if (!ref.mounted) return;
      state = DirectionsState(isLoading: false, error: e.type);
    } catch (_) {
      if (!ref.mounted) return;
      state = const DirectionsState(
        isLoading: false,
        error: LocationErrorType.networkFailure,
      );
    }
  }

  Future<void> retry() async => _initRoute();

  Future<void> launchExternalMaps(String shopName) async {
    if (state.shopLocation != null) {
      final locationService = ref.read(locationServiceProvider);
      await locationService.openExternalNavigation(state.shopLocation!, shopName);
    }
  }
}