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

  /// Accuracy of the fix in METRES, when the platform reported one.
  ///
  /// Deliberately NOT part of [==] or [hashCode]. A noisy reading and a precise
  /// reading of the SAME place are the same place: equality here means "these
  /// two name the same spot", and folding in the reading quality would make a
  /// cache keyed on coordinates miss purely because one fix was worse — which
  /// is how a saved address silently fails to match the current location.
  ///
  /// Null means "the platform did not say", which is NOT the same as 0. A 0
  /// would claim a fix is exactly on the reported point; coercing an unknown
  /// into 0 turns missing information into a false claim of precision.
  final double? accuracyMeters;

  const Coordinates(this.latitude, this.longitude, {this.accuracyMeters});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Coordinates &&
          other.latitude == latitude &&
          other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() =>
      'Coordinates(lat: $latitude, lng: $longitude, '
      'accuracy: ${accuracyMeters ?? 'unknown'})';
}

class LocationException implements Exception {
  final LocationErrorType type;
  final String message;

  const LocationException(this.type, this.message);

  @override
  String toString() => 'LocationException($type): $message';
}
