import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/location_repository.dart';
import '../domain/models/user_location.dart';
import '../../../core/error/failures.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';

class DeviceLocationRepository implements LocationRepository {
  final ApiClient? _apiClient;

  DeviceLocationRepository({this._apiClient});

  @override
  Future<bool> isLocationServiceEnabled() async => await Geolocator.isLocationServiceEnabled();

  @override
  Future<bool> checkPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
  }

  @override
  Future<bool> requestPermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const ServerFailure('Location permissions are permanently denied. Please enable in settings.');
    }
    return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
  }

  @override
  Future<UserLocation> getCurrentLocation() async {
    final hasPermission = await checkPermission();
    if (!hasPermission) throw const ServerFailure('Permission denied');

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );

    try {
      final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      final place = placemarks.first;

      return UserLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        address: '${place.street}, ${place.subLocality}',
        city: place.locality ?? place.subAdministrativeArea ?? 'Unknown City',
        state: place.administrativeArea ?? 'Unknown State',
        pincode: place.postalCode ?? '',
        isManual: false,
      );
    } catch (e) {
      // Fallback if reverse geocoding fails but we have coords for PostGIS
      return UserLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        address: 'Current Location',
        city: 'Unknown City',
        state: '',
        pincode: '',
        isManual: false,
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
      const UserLocation(latitude: 25.5941, longitude: 85.1376, address: 'Patna Center', city: 'Patna', state: 'Bihar', pincode: '800001', isManual: true),
      const UserLocation(latitude: 24.7914, longitude: 85.0002, address: 'Gaya Center', city: 'Gaya', state: 'Bihar', pincode: '823001', isManual: true),
      const UserLocation(latitude: 26.1209, longitude: 85.3647, address: 'Muzaffarpur Center', city: 'Muzaffarpur', state: 'Bihar', pincode: '842001', isManual: true),
    ];
    return mockCities.where((c) => c.city.toLowerCase().contains(query.toLowerCase())).toList();
  }
}

final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return DeviceLocationRepository(apiClient: ref.watch(apiClientProvider));
});