import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/location_models.dart';
import '../data/device_location_service.dart';

final locationServiceProvider = Provider<LocationService>(
  (ref) => DeviceLocationService(),
);

abstract class LocationService {
  Future<bool> isGpsEnabled();
  Future<bool> requestPermission();
  Future<Coordinates> getCurrentLocation();
  Future<void> openExternalNavigation(Coordinates destination, String label);
  double calculateDistance(Coordinates start, Coordinates end);
}
