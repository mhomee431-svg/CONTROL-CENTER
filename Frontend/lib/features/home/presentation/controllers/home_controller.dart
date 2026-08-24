import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../location/presentation/controllers/location_controller.dart';
import '../../domain/home_repository.dart';
import '../../domain/models/home_data.dart';

final homeControllerProvider = FutureProvider.autoDispose<HomeData>((ref) async {
  final repo = ref.watch(homeRepositoryProvider);
  // Best-effort coordinates: when the customer granted location access or
  // picked a manual location, the backend ranks nearby content by distance.
  final location = ref.watch(locationControllerProvider).location;
  final hasCoords = location != null && location.hasValidCoordinates;
  return await repo.fetchHomeFeed(
    latitude: hasCoords ? location.latitude : null,
    longitude: hasCoords ? location.longitude : null,
  );
});