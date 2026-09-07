/// A lightweight, map-SDK-agnostic latitude/longitude pair.
///
/// Kept separate from `google_maps_flutter.LatLng` so directions/geocoding
/// logic can be unit-tested without a platform channel.
class MapLatLng {
  const MapLatLng(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  bool get hasValidCoordinates =>
      latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MapLatLng &&
          other.latitude == latitude &&
          other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'MapLatLng(lat: $latitude, lng: $longitude)';
}

/// A decoded driving route returned by the Google Directions API.
///
/// `points` are the decoded polyline vertices in order (origin → destination).
class MapRoute {
  const MapRoute({
    required this.points,
    required this.distanceKm,
    required this.durationMinutes,
    this.encodedPolyline = '',
  });

  /// Decoded route vertices (origin → destination).
  final List<MapLatLng> points;

  /// Total route distance in kilometres.
  final double distanceKm;

  /// Total route duration in minutes.
  final double durationMinutes;

  /// Raw `overview_polyline.points` value (kept for tests / future caching).
  final String encodedPolyline;

  bool get isEmpty => points.isEmpty;

  String get distanceLabel => '${distanceKm.toStringAsFixed(1)} km';

  String get durationLabel => durationMinutes < 1
      ? '${(durationMinutes * 60).round()} sec'
      : '${durationMinutes.round()} min';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MapRoute && _samePoints(points, other.points);

  @override
  int get hashCode => Object.hashAll(points);

  static bool _samePoints(List<MapLatLng> a, List<MapLatLng> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}