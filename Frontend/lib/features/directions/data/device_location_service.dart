import 'dart:math';
import 'package:url_launcher/url_launcher.dart';
import '../domain/location_service.dart';
import '../domain/models/location_models.dart';

/// NOTE: In production, this utilizes the `geolocator` package.
/// Implemented as a mock here to ensure tests and UI run seamlessly
/// without real hardware dependencies.
class DeviceLocationService implements LocationService {
  bool _mockGpsEnabled = true;
  bool _mockPermissionGranted = true;

  /// Test helper to simulate GPS disabled state.
  void setMockGpsEnabled(bool enabled) => _mockGpsEnabled = enabled;

  /// Test helper to simulate permission denied state.
  void setMockPermissionGranted(bool granted) => _mockPermissionGranted = granted;

  @override
  Future<bool> isGpsEnabled() async => _mockGpsEnabled;

  @override
  Future<bool> requestPermission() async => _mockPermissionGranted;

  @override
  Future<Coordinates> getCurrentLocation() async {
    if (!_mockGpsEnabled) {
      throw const LocationException(LocationErrorType.noGps, 'GPS is disabled');
    }
    if (!_mockPermissionGranted) {
      throw const LocationException(
        LocationErrorType.permissionDenied,
        'Location permission denied',
      );
    }

    // Simulate hardware lock
    await Future.delayed(const Duration(milliseconds: 600));
    // Mock User Location (Delhi)
    return const Coordinates(28.7041, 77.1025);
  }

  @override
  Future<void> openExternalNavigation(Coordinates destination, String label) async {
    // Creates universal map intent url
    final url = Uri.parse(
      'geo:${destination.latitude},${destination.longitude}'
      '?q=${destination.latitude},${destination.longitude}($label)',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      // Fallback to web Maps if native intent fails (e.g., iOS)
      final webUrl = Uri.parse(
        'https://maps.google.com/?q=${destination.latitude},${destination.longitude}',
      );
      if (await canLaunchUrl(webUrl)) {
        await launchUrl(webUrl);
      }
    }
  }

  @override
  double calculateDistance(Coordinates start, Coordinates end) {
    // Haversine formula abstraction
    var p = 0.017453292519943295; // Math.PI / 180
    var a = 0.5 -
        cos((end.latitude - start.latitude) * p) / 2 +
        cos(start.latitude * p) *
            cos(end.latitude * p) *
            (1 - cos((end.longitude - start.longitude) * p)) / 2;
    return 12742 * asin(sqrt(a)); // Distance in km
  }
}