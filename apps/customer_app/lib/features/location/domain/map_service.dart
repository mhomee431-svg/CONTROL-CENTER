import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/google_map_service.dart';
import 'models/map_route.dart';
import 'models/user_location.dart';

/// The single seam through which the map screen talks to the Google Maps
/// web APIs (reverse geocoding + directions) and the native maps app.
///
/// Swap the concrete provider (Google Maps, here; Mapbox/OSM later) by
/// overriding [mapServiceProvider] at the app root or in tests — business
/// logic in the controller stays untouched.
final mapServiceProvider = Provider<MapService>((ref) {
  return GoogleMapService(
    dio: ref.watch(googleMapsDioProvider),
    polylineDecoder: ref.watch(polylineDecoderProvider),
  );
});

abstract class MapService {
  /// Reverse-geocodes a coordinate pair into a rich [UserLocation]
  /// (address, city, state, pincode) via the Google Geocoding API.
  Future<UserLocation> reverseGeocode({
    required double latitude,
    required double longitude,
  });

  /// Fetches a driving route and decodes the overview polyline via the
  /// Google Directions API.
  Future<MapRoute> fetchDrivingRoute({
    required MapLatLng origin,
    required MapLatLng destination,
  });

  /// Hands the destination over to the native maps app using the
  /// `google.navigation:` URI scheme.
  ///
  /// Returns `false` when no maps app / intent is available on the device.
  Future<bool> launchNavigation({
    required MapLatLng destination,
    String? label,
  });
}
