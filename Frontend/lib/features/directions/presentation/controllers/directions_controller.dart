import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/location_service.dart';
import '../../domain/models/location_models.dart';
import '../../../../features/shop_details/domain/shop_details_repository.dart';

/// Immutable state for the Directions feature.
class DirectionsState {
  final bool isLoading;
  final LocationErrorType? error;
  final Coordinates? userLocation;
  final Coordinates? shopLocation;
  final double? distanceInKm;
  final bool isShopClosed;

  const DirectionsState({
    this.isLoading = true,
    this.error,
    this.userLocation,
    this.shopLocation,
    this.distanceInKm,
    this.isShopClosed = false,
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

      // Fetch shop profile to get real shop coordinates.
      final shopRepo = ref.read(shopDetailsRepositoryProvider);
      final shopProfile = await shopRepo.getShopProfile(shopId);
      if (!ref.mounted) return;

      if (!shopProfile.hasValidCoordinates) {
        state = const DirectionsState(
          isLoading: false,
          error: LocationErrorType.invalidCoordinates,
        );
        return;
      }

      final userLoc = await locationService.getCurrentLocation();
      if (!ref.mounted) return;

      final shopLoc = Coordinates(shopProfile.latitude, shopProfile.longitude);
      final distance = locationService.calculateDistance(userLoc, shopLoc);

      state = DirectionsState(
        isLoading: false,
        userLocation: userLoc,
        shopLocation: shopLoc,
        distanceInKm: double.parse(distance.toStringAsFixed(2)),
        isShopClosed: !shopProfile.isOpenNow,
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