import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'map_providers_config.dart';

class RouteStep {
  const RouteStep({required this.instruction, required this.distanceText, required this.durationText});
  final String instruction;
  final String distanceText;
  final String durationText;
}

class DirectionsResult {
  const DirectionsResult({required this.polylinePoints, required this.distanceText, required this.durationText, this.steps = const [], required this.provider});
  final List<LatLng> polylinePoints;
  final String distanceText;
  final String durationText;
  final List<RouteStep> steps;
  final String provider;
}

class MapplsDirectionsService {
  MapplsDirectionsService._();
  static final MapplsDirectionsService instance = MapplsDirectionsService._();

  /// Get walking directions from origin to destination.
  /// Primary: Mappls (India-specific, lane-level navigation)
  /// Fallback: Google Directions API
  Future<DirectionsResult?> getWalkingDirections(LatLng origin, LatLng destination) async {
    if (MapProvidersConfig.mapplsEnabled) {
      final r = await _mapplsDirections(origin, destination);
      if (r != null) return r;
    }
    if (MapProvidersConfig.googleMapsEnabled) {
      return _googleDirections(origin, destination);
    }
    return null;
  }

  Future<DirectionsResult?> _mapplsDirections(LatLng origin, LatLng destination) async {
    return null; // Mappls REST API requires OAuth token flow
  }

  Future<DirectionsResult?> _googleDirections(LatLng origin, LatLng destination) async {
    return null; // Requires google_maps_webservice or manual REST integration
  }

  /// Build a straight-line polyline between two points (fallback when no API).
  List<LatLng> buildStraightLine(LatLng origin, LatLng destination) => [origin, destination];
}
