import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../domain/location_repository.dart';
import '../domain/models/location_exception.dart';
import '../domain/models/location_permission_status.dart';
import '../domain/models/user_location.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';

/// Device-based location provider using `geolocator` + `geocoding`.
///
/// This is the default implementation of [LocationRepository]. To swap
/// providers (e.g. Google Maps SDK, Mapbox), create a new class that
/// implements [LocationRepository] and override [locationRepositoryProvider].
class DeviceLocationRepository implements LocationRepository {
  final ApiClient? _apiClient;

  DeviceLocationRepository({this._apiClient});

  @override
  Future<bool> isLocationServiceEnabled() async =>
      await Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermissionStatus> checkPermission() async {
    final permission = await Geolocator.checkPermission();
    return _mapPermission(permission);
  }

  @override
  Future<LocationPermissionStatus> requestPermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return _mapPermission(permission);
  }

  LocationPermissionStatus _mapPermission(LocationPermission permission) {
    switch (permission) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationPermissionStatus.granted;
      case LocationPermission.denied:
        return LocationPermissionStatus.denied;
      case LocationPermission.deniedForever:
        return LocationPermissionStatus.permanentlyDenied;
      case LocationPermission.unableToDetermine:
        return LocationPermissionStatus.unknown;
    }
  }

  @override
  Future<UserLocation> getCurrentLocation() async {
    final permission = await checkPermission();
    if (permission != LocationPermissionStatus.granted) {
      throw LocationException(
        permission == LocationPermissionStatus.permanentlyDenied
            ? LocationErrorType.permissionPermanentlyDenied
            : LocationErrorType.permissionDenied,
        permission == LocationPermissionStatus.permanentlyDenied
            ? 'Location permission permanently denied. Please enable in settings.'
            : 'Location permission denied.',
      );
    }

    final serviceEnabled = await isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationException(
        LocationErrorType.serviceDisabled,
        'Location services are disabled. Please enable GPS.',
      );
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      if (position.latitude == 0 && position.longitude == 0) {
        throw const LocationException(
          LocationErrorType.invalidCoordinates,
          'Invalid coordinates received from GPS.',
        );
      }

      return await _buildLocationFromPosition(position);
    } on LocationException {
      rethrow;
    } catch (e) {
      throw LocationException(
        LocationErrorType.locationUnavailable,
        'Could not obtain a GPS fix: $e',
      );
    }
  }

  @override
  Future<UserLocation?> getLastKnownLocation() async {
    try {
      final position = await Geolocator.getLastKnownPosition();
      if (position == null) return null;
      return await _buildLocationFromPosition(position);
    } catch (_) {
      return null;
    }
  }

  Future<UserLocation> _buildLocationFromPosition(Position position) async {
    try {
      final placemarks = await Geocoding().placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      final place = placemarks.first;

      return UserLocation.withCapturedAt(
        latitude: position.latitude,
        longitude: position.longitude,
        address: '${place.street}, ${place.subLocality}',
        city: place.locality ?? place.subAdministrativeArea ?? 'Unknown City',
        state: place.administrativeArea ?? 'Unknown State',
        pincode: place.postalCode ?? '',
        label: place.locality ?? 'Current Location',
        isManual: false,
        isApproximate: false,
        accuracyMeters: position.accuracy,
        capturedAt: DateTime.now(),
      );
    } catch (e) {
      // Fallback if reverse geocoding fails but we have coords for PostGIS.
      // Mark as approximate so business logic can decide how to handle it.
      return UserLocation.withCapturedAt(
        latitude: position.latitude,
        longitude: position.longitude,
        address: 'Current Location',
        city: 'Unknown City',
        state: '',
        pincode: '',
        label: 'Current Location',
        isManual: false,
        isApproximate: true,
        accuracyMeters: position.accuracy,
        capturedAt: DateTime.now(),
      );
    }
  }

  @override
  Future<void> openLocationSettings() async => await Geolocator.openAppSettings();

  @override
  Future<List<UserLocation>> searchManualLocations(String query) async {
    // Try the backend first; fall back to local mock cities if the API is unavailable.
    if (_apiClient != null) {
      try {
        final data = await _apiClient.get(
          ApiEndpoints.manualLocationSearch,
          queryParameters: {'q': query},
          requiresAuth: false,
        );
        if (data is List) {
          return data
              .map((e) => UserLocation(
                    latitude: (e['latitude'] as num?)?.toDouble() ?? 0,
                    longitude: (e['longitude'] as num?)?.toDouble() ?? 0,
                    address: e['city']?.toString() ?? '',
                    city: e['city']?.toString() ?? '',
                    state: e['state']?.toString() ?? '',
                    pincode: e['pincode']?.toString() ?? '',
                    label: e['city']?.toString() ?? '',
                    isManual: true,
                  ))
              .toList();
        }
      } catch (_) {
        // Fall through to local mock data
      }
    }

    // Local fallback for Bihar target market
    final mockCities = [
      const UserLocation(latitude: 25.5941, longitude: 85.1376, address: 'Patna Center', city: 'Patna', state: 'Bihar', pincode: '800001', label: 'Patna', isManual: true),
      const UserLocation(latitude: 24.7914, longitude: 85.0002, address: 'Gaya Center', city: 'Gaya', state: 'Bihar', pincode: '823001', label: 'Gaya', isManual: true),
      const UserLocation(latitude: 26.1209, longitude: 85.3647, address: 'Muzaffarpur Center', city: 'Muzaffarpur', state: 'Bihar', pincode: '842001', label: 'Muzaffarpur', isManual: true),
    ];
    return mockCities.where((c) => c.city.toLowerCase().contains(query.toLowerCase())).toList();
  }
}