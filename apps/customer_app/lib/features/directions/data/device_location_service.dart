import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/env/env_config.dart';
import '../domain/location_service.dart';
import '../domain/models/location_models.dart';

/// Device GPS implementation of [LocationService].
///
/// In production builds it delegates to the real `geolocator` platform API
/// (permission + GPS fix). Debug/test builds keep the deterministic in-memory
/// behavior so the UI and controller tests run without hardware dependencies.
class DeviceLocationService implements LocationService {
  bool _mockGpsEnabled = true;
  bool _mockPermissionGranted = true;

  bool get _useRealGps => EnvConfig.isProduction;

  /// Test helper to simulate GPS disabled state.
  void setMockGpsEnabled(bool enabled) => _mockGpsEnabled = enabled;

  /// Test helper to simulate permission denied state.
  void setMockPermissionGranted(bool granted) => _mockPermissionGranted = granted;

  @override
  Future<bool> isGpsEnabled() async {
    if (_useRealGps) return Geolocator.isLocationServiceEnabled();
    return _mockGpsEnabled;
  }

  @override
  Future<bool> requestPermission() async {
    if (_useRealGps) {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    }
    return _mockPermissionGranted;
  }

  @override
  Future<Coordinates> getCurrentLocation() async {
    if (_useRealGps) {
      if (!await isGpsEnabled()) {
        throw const LocationException(
          LocationErrorType.noGps,
          'GPS is disabled',
        );
      }
      if (!await requestPermission()) {
        throw const LocationException(
          LocationErrorType.permissionDenied,
          'Location permission denied',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (position.latitude == 0 && position.longitude == 0) {
        throw const LocationException(
          LocationErrorType.invalidCoordinates,
          'Invalid coordinates received from GPS',
        );
      }
      return Coordinates(position.latitude, position.longitude);
    }

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