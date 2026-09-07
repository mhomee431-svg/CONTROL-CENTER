import 'package:dio/dio.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/env/env_config.dart';
import '../domain/map_service.dart';
import '../domain/models/location_exception.dart';
import '../domain/models/map_route.dart';
import '../domain/models/user_location.dart';

/// Decodes Google's "Encoded Polyline Algorithm Format" strings.
///
/// Hidden behind an interface so the directions parser can be unit-tested
/// with a fake decoder (and a different polyline lib could be swapped in).
abstract class PolylineDecoder {
  List<MapLatLng> decodePolyline(String encoded);
}

/// Production decoder backed by `flutter_polyline_points`.
class FlutterPolylinePointsDecoder implements PolylineDecoder {
  const FlutterPolylinePointsDecoder();

  @override
  List<MapLatLng> decodePolyline(String encoded) {
    final points = PolylinePoints.decodePolyline(encoded);
    return [for (final p in points) MapLatLng(p.latitude, p.longitude)];
  }
}

final polylineDecoderProvider = Provider<PolylineDecoder>((ref) {
  return const FlutterPolylinePointsDecoder();
});

/// Standalone HTTP client for the Google Maps web APIs.
///
/// Deliberately separate from `apiClientProvider` (which targets the
/// Hyperlocal backend and unwraps the `{success, data}` envelope): the
/// Google endpoints speak native JSON and use the `MAPS_API_KEY` instead
/// of the user session.
final googleMapsDioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      baseUrl: 'https://maps.googleapis.com',
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
      responseType: ResponseType.json,
    ),
  );
});
/// Google Maps Geocoding + Directions REST implementation of [MapService].
class GoogleMapService implements MapService {
  GoogleMapService({
    required this._dio,
    required this.polylineDecoder,
  });

  final Dio _dio;
  final PolylineDecoder polylineDecoder;

  static const _geocodeEndpoint = '/maps/api/geocode/json';
  static const _directionsEndpoint = '/maps/api/directions/json';

  @override
  Future<UserLocation> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    _ensureKeyConfigured();
    try {
      final response = await _dio.get(
        _geocodeEndpoint,
        queryParameters: {
          'latlng': '$latitude,$longitude',
          'key': EnvConfig.mapsApiKey,
          'language': 'en',
          'region': 'IN',
          'result_type':
              'street_address|route|sublocality|locality|administrative_area_level_2|administrative_area_level_1|postal_code',
        },
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const LocationException(
          LocationErrorType.networkFailure,
          'Unexpected reverse-geocoding response.',
        );
      }
      final parsed = reverseGeocodeFromJson(
        data,
        latitude: latitude,
        longitude: longitude,
      );
      if (parsed == null) {
        throw const LocationException(
          LocationErrorType.networkFailure,
          'No address found for this location.',
        );
      }
      return parsed;
    } on DioException catch (e) {
      throw LocationException(
        LocationErrorType.networkFailure,
        'Reverse geocoding failed: ${e.message}',
      );
    }
  }

  @override
  Future<MapRoute> fetchDrivingRoute({
    required MapLatLng origin,
    required MapLatLng destination,
  }) async {
    _ensureKeyConfigured();
    try {
      final response = await _dio.get(
        _directionsEndpoint,
        queryParameters: {
          'origin': '${origin.latitude},${origin.longitude}',
          'destination': '${destination.latitude},${destination.longitude}',
          'mode': 'driving',
          'units': 'metric',
          'alternatives': 'false',
          'key': EnvConfig.mapsApiKey,
        },
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const LocationException(
          LocationErrorType.networkFailure,
          'Unexpected directions response.',
        );
      }
      final route = directionsFromJson(data, polylineDecoder);
      if (route == null || route.points.isEmpty) {
        throw const LocationException(
          LocationErrorType.networkFailure,
          'No route could be found between these points.',
        );
      }
      return route;
    } on DioException catch (e) {
      throw LocationException(
        LocationErrorType.networkFailure,
        'Directions request failed: ${e.message}',
      );
    }
  }

  @override
  Future<bool> launchNavigation({
    required MapLatLng destination,
    String? label,
  }) async {
    final coords = '${destination.latitude},${destination.longitude}';
    // Native Google Maps app navigation, e.g. google.navigation:q=25.59,85.13
    final navigationUri = Uri.parse('google.navigation:q=$coords&mode=d');
    if (await canLaunchUrl(navigationUri)) {
      return launchUrl(navigationUri);
    }
    // Universal web fallback (also redirects into the native app).
    final webUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$coords'
      '&travelmode=driving',
    );
    if (await canLaunchUrl(webUri)) {
      return launchUrl(webUri);
    }
    return false;
  }

  void _ensureKeyConfigured() {
    if (EnvConfig.mapsApiKey.isEmpty) {
      throw const LocationException(
        LocationErrorType.networkFailure,
        'Maps API key is not configured. '
        'Run with --dart-define=MAPS_API_KEY=your_key',
      );
    }
  }
}
// ── Pure parsing helpers (unit-testable without network) ────────────────

const _typesSeparator = '|';

/// Parses a Google Geocoding API response into a [UserLocation].
///
/// Returns `null` when the API status is not `OK` or no result is present.
UserLocation? reverseGeocodeFromJson(
  Map<String, dynamic> json, {
  required double latitude,
  required double longitude,
}) {
  if (json['status'] != 'OK') return null;
  final results = json['results'];
  if (results is! List || results.isEmpty) return null;

  final place = results.first;

  if (place is! Map) return null;
  final rawComponents = place['address_components'];
  final components = <Map<String, String>>[];
  if (rawComponents is List) {
    for (final raw in rawComponents) {
      if (raw is! Map) continue;
      final types = (raw['types'] as List?) ?? const [];
      components.add({
        'long_name': (raw['long_name'] ?? '').toString(),
        'short_name': (raw['short_name'] ?? '').toString(),
        'types': types.join(_typesSeparator),
      });
    }
  }


  String componentFor(String type) {
    for (final c in components) {
      if ((c['types'] ?? '').split(_typesSeparator).contains(type)) {
        return c['long_name'] ?? '';
      }
    }
    return '';
  }


  final streetNumber = componentFor('street_number');
  final route = componentFor('route');
  final neighborhood = componentFor('neighborhood');
  final subLocality1 = componentFor('sublocality_level_1');
  final subLocality2 = componentFor('sublocality_level_2');
  final locality = componentFor('locality');
  final district = componentFor('administrative_area_level_2');
  final state = componentFor('administrative_area_level_1');
  final pincode = componentFor('postal_code');
  final formatted = place['formatted_address']?.toString() ?? '';


  final addressParts = <String>[
    if (streetNumber.isNotEmpty) streetNumber,
    if (route.isNotEmpty) route,
    if (neighborhood.isNotEmpty) neighborhood,
    if (subLocality1.isNotEmpty) subLocality1,
    if (subLocality2.isNotEmpty) subLocality2,
  ];
  var address = addressParts.join(', ');
  if (address.isEmpty && formatted.isNotEmpty) {
    // Fall back to the street-level portion of the formatted address.

    address = formatted.split(',').first.trim();
  }


  final city = locality.isNotEmpty
      ? locality
      : (district.isNotEmpty ? district : subLocality1);
  final label = city.isNotEmpty ? city : 'Pinned location';


  return UserLocation.withCapturedAt(
    latitude: latitude,
    longitude: longitude,
    address: address,
    city: city,
    state: state,
    pincode: pincode,
    label: label,
    isManual: false,
    isApproximate: false,
    capturedAt: DateTime.now(),
  );
}

/// Parses a Google Directions API response into a [MapRoute].
///
/// Returns `null` when the API status is not `OK`, no route exists, or the
/// overview polyline cannot be decoded.
MapRoute? directionsFromJson(Map<String, dynamic> json, PolylineDecoder decoder) {

  if (json['status'] != 'OK') return null;
  final routes = json['routes'];
  if (routes is! List || routes.isEmpty) return null;


  final route = routes.first;



  if (route is! Map) return null;


  var distanceMetres = 0.0;
  var durationSeconds =  0.0;
  final legs = route['legs'];
  if (legs is List) {
    for (final leg in legs) {
      if (leg is! Map) continue;
      final distance = leg['distance'];
      final duration = leg['duration'];
      distanceMetres +=
          (distance is Map ? (distance['value'] as num?)?.toDouble() : 0) ?? 0;
      durationSeconds +=
          (duration is Map ? (duration['value'] as num?)?.toDouble() : 0) ?? 0;
    }
  }


  final overview = route['overview_polyline'];
  final encoded = overview is Map ? (overview['points'] ?? '' ).toString() : '';
  final points = decoder.decodePolyline(encoded);
  if (points.isEmpty) return null;


  return MapRoute(
    points: points,
    distanceKm: distanceMetres / 1000,
    durationMinutes: durationSeconds / 60,
    encodedPolyline: encoded,
  );
}