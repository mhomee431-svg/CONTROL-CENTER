import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/device_location_repository.dart';
import 'models/location_permission_status.dart';
import 'models/user_location.dart';

/// Provider for the location repository.
///
/// To swap the underlying location provider (geolocator, google_maps,
/// mapbox, etc.), replace this with a different implementation of
/// [LocationRepository]. Business logic in controllers/services
/// remains untouched.
final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return DeviceLocationRepository(apiClient: ref.watch(apiClientProvider));
});

/// Abstraction over the device/backend location provider.
///
/// This is the single seam through which all location data flows.
/// Implementations can use geolocator, a map SDK, or a mock for tests.
abstract class LocationRepository {
  /// Whether the device location service (GPS) is enabled.
  Future<bool> isLocationServiceEnabled();

  /// Current permission status without prompting the user.
  Future<LocationPermissionStatus> checkPermission();

  /// Requests location permission from the user.
  ///
  /// Returns the resulting [LocationPermissionStatus]. If the user has
  /// permanently denied, this will return [LocationPermissionStatus.permanentlyDenied]
  /// without showing a prompt.
  Future<LocationPermissionStatus> requestPermission();

  /// Retrieves the current device location (GPS).
  ///
  /// Throws a [LocationException] if permission is missing, GPS is off,
  /// or the fix is unavailable.
  Future<UserLocation> getCurrentLocation();

  /// Retrieves the last known position without triggering a new GPS fix.
  ///
  /// Returns `null` if no cached position exists. This is used to avoid
  /// repeated location requests when a fresh fix isn't needed.
  Future<UserLocation?> getLastKnownLocation();

  /// Opens the system location settings so the user can enable GPS
  /// or grant permission that was permanently denied.
  Future<void> openLocationSettings();

  /// Searches for a location by name (city, area, PIN code).
  Future<List<UserLocation>> searchManualLocations(String query);
}
