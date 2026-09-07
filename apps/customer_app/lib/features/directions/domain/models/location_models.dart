enum LocationErrorType {
  noGps,
  permissionDenied,
  permissionPermanentlyDenied,
  invalidCoordinates,
  networkFailure,
}

class Coordinates {
  final double latitude;
  final double longitude;

  const Coordinates(this.latitude, this.longitude);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Coordinates &&
          other.latitude == latitude &&
          other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'Coordinates(lat: $latitude, lng: $longitude)';
}

class LocationException implements Exception {
  final LocationErrorType type;
  final String message;

  const LocationException(this.type, this.message);

  @override
  String toString() => 'LocationException($type): $message';
}