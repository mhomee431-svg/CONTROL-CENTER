import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../data/device_location_repository.dart';
import 'models/user_location.dart';

final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return DeviceLocationRepository(apiClient: ref.watch(apiClientProvider));
});

abstract class LocationRepository {
  Future<UserLocation> getCurrentLocation();
  Future<bool> checkPermission();
  Future<bool> requestPermission();
  Future<bool> isLocationServiceEnabled();
  Future<void> openLocationSettings();
  Future<List<UserLocation>> searchManualLocations(String query);
}