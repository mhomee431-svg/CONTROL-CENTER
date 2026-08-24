/// Types of location-related errors that can occur.
enum LocationErrorType {
  /// GPS / location service is disabled on the device.
  serviceDisabled,

  /// User denied location permission (can be asked again).
  permissionDenied,

  /// User permanently denied location permission (must use settings).
  permissionPermanentlyDenied,

  /// Permission is restricted by policy (parental controls, MDM).
  permissionRestricted,

  /// Coordinates are invalid or out of real-world bounds.
  invalidCoordinates,

  /// Location is approximate and not suitable for nearby discovery.
  approximateLocation,

  /// GPS fix could not be obtained (timeout, no signal).
  locationUnavailable,

  /// Network failure (e.g. reverse geocoding failed).
  networkFailure,
}

/// Exception thrown by location providers.
class LocationException implements Exception {
  final LocationErrorType type;
  final String message;

  const LocationException(this.type, this.message);

  @override
  String toString() => 'LocationException($type): $message';
}