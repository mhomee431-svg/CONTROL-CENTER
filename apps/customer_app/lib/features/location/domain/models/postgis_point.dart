/// PostGIS-compatible point representation for backend integration.
///
/// PostGIS stores points as `POINT(longitude latitude)` in SRID 4326
/// (WGS 84). This model provides:
///   - `toWkt()`  → `POINT(85.1376 25.5941)` for direct SQL/GeoAlchemy use
///   - `toGeoJson()` → `{"type":"Point","coordinates":[lng,lat]}` for REST APIs
///   - `toQueryParams()` → `{lat, lng}` for simple query-string APIs
///
/// Note: GeoJSON uses [longitude, latitude] order, while WKT uses
/// `POINT(longitude latitude)` — both are longitude-first.
class PostGisPoint {
  final double latitude;
  final double longitude;

  const PostGisPoint({required this.latitude, required this.longitude});

  /// Well-Known Text (WKT) — `POINT(lng lat)` for PostGIS/GeoAlchemy.
  String toWkt() => 'POINT($longitude $latitude)';

  /// GeoJSON Point — `{"type":"Point","coordinates":[lng,lat]}`.
  Map<String, dynamic> toGeoJson() => {
    'type': 'Point',
    'coordinates': [longitude, latitude],
  };

  /// Simple query params for REST endpoints expecting lat/lng.
  Map<String, dynamic> toQueryParams() => {'lat': latitude, 'lng': longitude};

  /// Validates that coordinates are within real-world bounds.
  bool get isValid =>
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PostGisPoint &&
          other.latitude == latitude &&
          other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'PostGisPoint(lat: $latitude, lng: $longitude)';
}
