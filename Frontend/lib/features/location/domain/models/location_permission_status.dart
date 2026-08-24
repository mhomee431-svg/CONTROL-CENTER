/// Represents the current state of location permission on the device.
///
/// This is a provider-agnostic abstraction so that the underlying
/// permission implementation (geolocator, permission_handler, etc.)
/// can be swapped without touching business logic.
enum LocationPermissionStatus {
  /// Permission has been granted (always or while-in-use).
  granted,

  /// Permission has been denied by the user, but they can be asked again.
  denied,

  /// Permission has been permanently denied. The user must change
  /// this in system settings — requesting again will not show a prompt.
  permanentlyDenied,

  /// Permission is restricted (e.g. parental controls, MDM policy).
  restricted,

  /// Permission state is unknown (e.g. first launch, platform error).
  unknown,
}