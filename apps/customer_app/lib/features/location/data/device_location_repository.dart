// ignore_for_file: prefer_initializing_formals — private fields can't use this._
import 'package:dio/dio.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../domain/location_repository.dart';
import '../domain/models/location_exception.dart';
import '../domain/models/location_permission_status.dart';
import '../domain/models/user_location.dart';
import '../../../core/env/env_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/security/safe_logger.dart';

/// Device-based location provider using `geolocator` + Google Geocoding API.
///
/// Reverse geocoding uses the Google Geocoding REST API (not the native
/// Android Geocoder) for reliable area / city / pincode extraction across
/// India — the same implementation the map picker uses.
class DeviceLocationRepository implements LocationRepository {
  final ApiClient? _apiClient;
  final Dio _googleMapsDio;

  DeviceLocationRepository({ApiClient? apiClient, Dio? googleMapsDio})
    : _apiClient = apiClient,
      _googleMapsDio =
          googleMapsDio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://maps.googleapis.com',
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 12),
              responseType: ResponseType.json,
            ),
          );

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
    // If permanently denied, requestPermission() won't show a dialog — map it.
    if (permission == LocationPermission.deniedForever) {
      return LocationPermissionStatus.permanentlyDenied;
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
    // 1. Request permission — shows the system dialog if not yet granted.
    final permission = await requestPermission();

    SafeLogger.debug('Device location permission=$permission');
    if (permission == LocationPermissionStatus.permanentlyDenied) {
      throw const LocationException(
        LocationErrorType.permissionPermanentlyDenied,
        'Location permission permanently denied. Please enable in settings.',
      );
    }

    if (permission != LocationPermissionStatus.granted) {
      throw const LocationException(
        LocationErrorType.permissionDenied,
        'Location permission denied.',
      );
    }

    // 2. Ensure location services (GPS) are turned on.
    final serviceEnabled = await isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationException(
        LocationErrorType.serviceDisabled,
        'Location services are disabled. Please enable GPS.',
      );
    }

    // 3. Get a high-accuracy GPS fix.
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

      SafeLogger.debug('GPS fix obtained from current position.');
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
      SafeLogger.debug('GPS fix obtained from last known position.');
      return await _buildLocationFromPosition(position);
    } catch (_) {
      return null;
    }
  }

  /// True when a GPS accuracy reading is too coarse to call "precise".
  ///
  /// A non-positive accuracy means the device did not report one — that is
  /// "unknown", which is not the same as perfect, so it is never precise.
  static bool _isCoarse(double accuracyMeters) =>
      accuracyMeters <= 0 ||
      accuracyMeters > UserLocation.poorAccuracyThresholdMeters;

  /// Reverse-geocodes [position] into a rich [UserLocation] (area / city /
  /// pincode). Uses Nominatim (OpenStreetMap) as the primary geocoder because
  /// it is free, needs no API key, and works in India — so the app delivers
  /// live area + city + pincode regardless of how a Google key is restricted.
  /// Falls back to an approximate (coordinates-only) location if the network
  /// is unreachable or returns no result, so nearby-shop discovery still works.
  Future<UserLocation> _buildLocationFromPosition(Position position) async {
    // 1. NATIVE Android Geocoder — uses Google Play Services on the device.
    //    No API key, no web service, no IP blocking. Most reliable on Android.
    final native = await _reverseGeocodeNative(position);
    if (native != null) return native;

    // 2. Optional fallback: Google Geocoding API (only when a key is configured
    /// and its restrictions allow web-service calls). Harmless no-op otherwise.
    final google = await _reverseGeocodeGoogle(position);
    if (google != null) return google;

    // 3. Last resort: coordinates only, marked approximate.
    return UserLocation.withCapturedAt(
      latitude: position.latitude,
      longitude: position.longitude,
      address: 'Current Location',
      city: '',
      state: '',
      pincode: '',
      label: 'Current Location',
      isManual: false,
      isApproximate: true,
      accuracyMeters: position.accuracy,
      capturedAt: DateTime.now(),
    );
  }

  /// Reverse-geocodes using the NATIVE Android Geocoder (Google Play Services).
  /// No API key, no web service, no IP blocking. Returns null on any failure.
  Future<UserLocation?> _reverseGeocodeNative(Position position) async {
    try {
      final geocoding = Geocoding();
      final placemarks = await geocoding.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isEmpty) return null;
      final place = placemarks.first;

      SafeLogger.debug('Native geocoder returned a location result.');

      // All Placemark fields are nullable in geocoding v5 — normalize to ''.
      String s(String? v) => (v ?? '').trim();

      // Area / sublocality - the Zepto-style headline.
      final areaParts = <String>[
        if (s(place.subLocality).isNotEmpty) s(place.subLocality),
        if (s(place.subAdministrativeArea).isNotEmpty)
          s(place.subAdministrativeArea),
        if (s(place.name).isNotEmpty) s(place.name),
      ];
      var area = areaParts.join(', ');

      final city = s(place.locality).isNotEmpty
          ? s(place.locality)
          : (s(place.subAdministrativeArea).isNotEmpty
                ? s(place.subAdministrativeArea)
                : s(place.administrativeArea));
      final state = s(place.administrativeArea);
      final pincode = s(place.postalCode);
      final label = city.isNotEmpty ? city : 'Current Location';

      return UserLocation.withCapturedAt(
        latitude: position.latitude,
        longitude: position.longitude,
        address: area,
        city: city,
        state: state,
        pincode: pincode,
        label: label,
        isManual: false,
        // Carry the device's real accuracy through, and downgrade to
        // "approximate" when the fix is too coarse to call precise.
        isApproximate: _isCoarse(position.accuracy),
        accuracyMeters: position.accuracy > 0 ? position.accuracy : 0,
        capturedAt: DateTime.now(),
      );
    } catch (e, stack) {
      SafeLogger.warning('Native reverse geocoder failed: $e');
      SafeLogger.debug(stack.toString());
      return null;
    }
  }

  /// Reverse-geocodes via Google Geocoding API. Returns null if the key is empty
  /// or the call fails (e.g. key restricted to Android apps only).
  Future<UserLocation?> _reverseGeocodeGoogle(Position position) async {
    if (EnvConfig.mapsApiKey.isEmpty) return null;
    try {
      final response = await _googleMapsDio.get(
        '/maps/api/geocode/json',
        queryParameters: {
          'latlng': '${position.latitude},${position.longitude}',
          'key': EnvConfig.mapsApiKey,
          'language': 'en',
          'region': 'IN',
          'result_type': 'street_address|route|sublocality|locality|administrative_area_level_2|administrative_area_level_1|postal_code',
        },
      );
      return _reverseGeocodeFromJson(
        response.data,
        position.latitude,
        position.longitude,
        accuracyMeters: position.accuracy,
      );
    } catch (e, stack) {
      SafeLogger.warning('Google reverse geocoder failed: $e');
      SafeLogger.debug(stack.toString());
      return null;
    }
  }

  /// Parses a Google Geocoding API response into a [UserLocation], extracting
  /// area / sublocality, city, state and pincode from the address components.
  UserLocation? _reverseGeocodeFromJson(
    Map<String, dynamic> json,
    double latitude,
    double longitude, {
    double accuracyMeters = 0,
  }) {
    if (json['status'] != 'OK') return null;
    final results = json['results'];
    if (results is! List || results.isEmpty) return null;

    final place = results.first;
    if (place is! Map) return null;

    final addressComponents = place['address_components'];
    final components = <Map<String, String>>[];

    if (addressComponents is List) {
      for (final component in addressComponents) {
        if (component is! Map) continue;
        final types = (component['types'] as List?) ?? const [];
        components.add({
          'long_name': (component['long_name'] ?? '').toString(),
          'short_name': (component['short_name'] ?? '').toString(),
          'types': types.join('|'),
        });
      }
    }

    String componentFor(String type) {
      for (final c in components) {
        if ((c['types'] ?? '').split('|').contains(type)) {
          return c['long_name'] ?? '';
        }
      }
      return '';
    }

    final neighborhood = componentFor('neighborhood');
    final subLocality1 = componentFor('sublocality_level_1');
    final subLocality2 = componentFor('sublocality_level_2');
    final route = componentFor('route');
    final locality = componentFor('locality');
    final district = componentFor('administrative_area_level_2');
    final state = componentFor('administrative_area_level_1');
    final pincode = componentFor('postal_code');
    final formatted = place['formatted_address']?.toString() ?? '';

    // Area / sublocality - the Zepto-style area line.
    final areaParts = <String>[
      if (subLocality1.isNotEmpty) subLocality1,
      if (subLocality2.isNotEmpty) subLocality2,
      if (neighborhood.isNotEmpty) neighborhood,
      if (route.isNotEmpty) route,
    ];
    var area = areaParts.join(', ');
    if (area.isEmpty && formatted.isNotEmpty) {
      area = formatted.split(',').first.trim();
    }

    final city = locality.isNotEmpty
        ? locality
        : (district.isNotEmpty ? district : subLocality1);
    final label = city.isNotEmpty ? city : 'Current Location';

    return UserLocation.withCapturedAt(
      latitude: latitude,
      longitude: longitude,
      address: area,
      city: city,
      state: state,
      pincode: pincode,
      label: label,
      isManual: false,
      // The geocoder refines the *address*, never the GPS fix itself — so the
      // device's accuracy carries through unchanged and the result is marked
      // approximate when that fix was coarse.
      isApproximate: _isCoarse(accuracyMeters),
      accuracyMeters: accuracyMeters > 0 ? accuracyMeters : 0,
      capturedAt: DateTime.now(),
    );
  }

  @override
  Future<void> openLocationSettings() async {
    // Geolocator.openAppSettings() is unsupported on web and throws; guard
    // it so callers (permission dialogs) never crash on that platform.
    try {
      await Geolocator.openAppSettings();
    } catch (_) {
      // No-op where app-settings deep links don't exist (web).
    }
  }

  @override
  Future<List<UserLocation>> searchManualLocations(String query) async {
    // Backend is authoritative in staging/production. In development the API
    // may be absent, so fall back to a small local list — never in release.
    if (_apiClient != null) {
      try {
        final data = await _apiClient.get(
          ApiEndpoints.manualLocationSearch,
          queryParameters: {'q': query},
          requiresAuth: false,
        );
        if (data is List) {
          return data
              .map(
                (e) => UserLocation(
                  latitude: (e['latitude'] as num?)?.toDouble() ?? 0,
                  longitude: (e['longitude'] as num?)?.toDouble() ?? 0,
                  address: e['city']?.toString() ?? '',
                  city: e['city']?.toString() ?? '',
                  state: e['state']?.toString() ?? '',
                  pincode: e['pincode']?.toString() ?? '',
                  label: e['city']?.toString() ?? '',
                  isManual: true,
                ),
              )
              .toList();
        }
      } catch (_) {
        if (EnvConfig.isProduction) {
          // Backend is the only source of truth in production — surface the
          // failure instead of fabricating results client-side.
          rethrow;
        }
      }
    }

    if (EnvConfig.isProduction) {
      return const [];
    }

    // Local fallback for the Bihar target market (development only).
    final mockCities = [
      const UserLocation(
        latitude: 25.5941,
        longitude: 85.1376,
        address: 'Patna Center',
        city: 'Patna',
        state: 'Bihar',
        pincode: '800001',
        label: 'Patna',
        isManual: true,
      ),
      const UserLocation(
        latitude: 24.7914,
        longitude: 85.0002,
        address: 'Gaya Center',
        city: 'Gaya',
        state: 'Bihar',
        pincode: '823001',
        label: 'Gaya',
        isManual: true,
      ),
      const UserLocation(
        latitude: 26.1209,
        longitude: 85.3647,
        address: 'Muzaffarpur Center',
        city: 'Muzaffarpur',
        state: 'Bihar',
        pincode: '842001',
        label: 'Muzaffarpur',
        isManual: true,
      ),
    ];
    return mockCities
        .where((c) => c.city.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }
}
