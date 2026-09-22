import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'geocoding_service.dart';
import 'location_accuracy_config.dart';

/// Result of the full permission/service pre-flight check.
class GpsReading {
  const GpsReading({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.accuracy,
    this.altitude,
    this.speed,
    this.isMock = false,
  });

  factory GpsReading.fromPosition(Position p) => GpsReading(
        latitude: p.latitude,
        longitude: p.longitude,
        timestamp: p.timestamp,
        accuracy: p.hasAccuracy ? p.accuracy : null,
        altitude: p.hasAltitude ? p.altitude : null,
        speed: p.hasSpeed ? p.speed : null,
        // geolocator's platform mock-location signal (informative only —
        // never treated as tamper-proof; stored as location_integrity_status).
        isMock: p.isMocked,
      );

  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double? accuracy;
  final double? altitude;
  final double? speed;

  /// Client-side mock-location signal (informative only — never tamper-proof).
  final bool isMock;

  bool get hasValidCoordinates =>
      latitude.abs() <= 90 && longitude.abs() <= 180;

  AccuracyTier get tier => LocationAccuracyConfig.tierFor(accuracy);

  bool get isMockOrUnknown => isMock;

  /// True when the reading is older than the configured max age.
  bool isStale({DateTime? now}) =>
      LocationAccuracyConfig.isStale(timestamp, now: now);
}

/// Result of the full permission/service pre-flight check.
class LocationPermissionStatus {
  const LocationPermissionStatus({
    required this.serviceEnabled,
    required this.permission,
  });

  final bool serviceEnabled;
  final LocationPermission permission;

  bool get granted =>
      permission == LocationPermission.whileInUse ||
      permission == LocationPermission.always;

  bool get deniedForever => permission == LocationPermission.deniedForever;

  /// geolocator exposes a single coarse permission on Android; precise
  /// availability is approximated via the platform permission state.
  bool get preciseAvailable => granted;
}

/// A picked map location with reverse-geocoded address (shop pin).
class PickedLocation {
  const PickedLocation({
    required this.latitude,
    required this.longitude,
    this.addressLine,
    this.area,
    this.city,
    this.district,
    this.state,
    this.pincode,
    this.country,
  });

  final double latitude;
  final double longitude;
  final String? addressLine;
  final String? area;
  final String? city;
  final String? district;
  final String? state;
  final String? pincode;
  final String? country;

  /// Multi-line display form: Ghusiya Kala / Bikramganj / Rohtas / Bihar / India.
  List<String> get displayLines => [
        if (addressLine != null && addressLine!.trim().isNotEmpty)
          addressLine!.trim(),
        if (area != null && area!.trim().isNotEmpty) area!.trim(),
        if (city != null && city!.trim().isNotEmpty) city!.trim(),
        if (district != null && district!.trim().isNotEmpty) district!.trim(),
        if (state != null && state!.trim().isNotEmpty) state!.trim(),
        if (pincode != null && pincode!.trim().isNotEmpty) pincode!.trim(),
        if (country != null && country!.trim().isNotEmpty) country!.trim(),
      ];

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        if (addressLine != null) 'address_line': addressLine,
        if (area != null) 'area': area,
        if (city != null) 'city': city,
        if (district != null) 'district': district,
        if (state != null) 'state': state,
        if (pincode != null) 'pincode': pincode,
        if (country != null) 'country': country,
      };

  factory PickedLocation.fromJson(Map<String, dynamic> json) => PickedLocation(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        addressLine: json['address_line'] as String?,
        area: json['area'] as String?,
        city: json['city'] as String?,
        district: json['district'] as String?,
        state: json['state'] as String?,
        pincode: json['pincode'] as String?,
        country: json['country'] as String?,
      );
}

/// Aggregate result of a multi-reading acquisition session.
class LocationAcquisition {
  const LocationAcquisition({
    required this.best,
    required this.readings,
    required this.timedOut,
  });

  /// Best valid reading (smallest accuracy radius, most recent).
  final GpsReading? best;
  final List<GpsReading> readings;

  /// True when acquisition ended on the overall timeout rather than reaching
  /// the target accuracy ("Best available location found").
  final bool timedOut;

  bool get hasUsableLocation => best != null && best!.hasValidCoordinates;

  AccuracyTier get tier => best?.tier ?? AccuracyTier.unknown;
}

/// Pure (platform-free) acquisition helpers — unit-tested without a device.
class LocationAcquisitionEngine {
  const LocationAcquisitionEngine._();

  /// Selects the best valid reading:
  ///   1. discard invalid coordinates and obviously poor readings,
  ///   2. smallest accuracy radius wins,
  ///   3. ties broken by the most recent timestamp.
  ///
  /// When [includeMock] is false (default), mock-flagged readings are
  /// excluded. If that leaves no candidates, pass [includeMock: true] to
  /// fall back to mock readings rather than returning nothing.
  static GpsReading? bestOf(Iterable<GpsReading> readings, {bool includeMock = false}) {
    var valid = readings
        .where((r) => r.hasValidCoordinates)
        .where((r) =>
            r.accuracy == null ||
            r.accuracy! <= LocationAccuracyConfig.discardAboveMeters);
    if (!includeMock) {
      valid = valid.where((r) => !r.isMockOrUnknown);
    }
    final list = valid.toList(growable: false);
    if (list.isEmpty) return null;
    GpsReading best = list.first;
    for (final r in list.skip(1)) {
      final bestAcc = best.accuracy ?? double.infinity;
      final acc = r.accuracy ?? double.infinity;
      if (acc < bestAcc ||
          (acc == bestAcc && r.timestamp.isAfter(best.timestamp))) {
        best = r;
      }
    }
    return best;
  }

  /// True when the reading is good enough to stop acquiring early.
  static bool reachedTarget(GpsReading reading) =>
      reading.hasValidCoordinates &&
      (reading.accuracy ?? double.infinity) <=
          LocationAccuracyConfig.targetAccuracyMeters;
}

/// Abstraction over the platform position provider (injectable in tests).
abstract class PositionSource {
  Future<LocationPermissionStatus> resolvePermission();
  Future<GpsReading> readOnce({Duration? timeLimit});
  Stream<GpsReading> readStream({required int distanceFilterMeters});
}

class GeolocatorPositionSource implements PositionSource {
  const GeolocatorPositionSource();

  @override
  Future<LocationPermissionStatus> resolvePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    debugPrint('[LOC] serviceEnabled=$serviceEnabled');
    var permission = await Geolocator.checkPermission();
    debugPrint('[LOC] checkPermission=$permission');
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      debugPrint('[LOC] requestPermission=$permission');
    }
    return LocationPermissionStatus(
      serviceEnabled: serviceEnabled,
      permission: permission,
    );
  }

  @override
  Future<GpsReading> readOnce({Duration? timeLimit}) async {
    // Fast path: try last-known position first (instant, no GPS wait).
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        final age = DateTime.now().difference(lastKnown.timestamp);
        // Use last-known if it's fresh enough (< 2 minutes).
        if (age.inMinutes < 2) {
          debugPrint('[LOC] Using last-known position (${age.inSeconds}s old)');
          return GpsReading.fromPosition(lastKnown);
        }
        debugPrint('[LOC] Last-known too old (${age.inMinutes}min), fetching fresh...');
      } else {
        debugPrint('[LOC] No last-known position, fetching fresh...');
      }
    } catch (e) {
      debugPrint('[LOC] getLastKnownPosition error: $e');
    }

    // Slow path: get a fresh high-accuracy GPS fix.
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracyConfig.geolocatorAccuracy,
          timeLimit: timeLimit ?? LocationAccuracyConfig.singleReadingTimeLimit,
        ),
      );
      debugPrint('[LOC] Fresh GPS fix: ${position.latitude}, ${position.longitude} (acc: ${position.accuracy}m)');
      return GpsReading.fromPosition(position);
    } catch (e) {
      debugPrint('[LOC] getCurrentPosition error: $e');
      rethrow;
    }
  }

  @override
  Stream<GpsReading> readStream({required int distanceFilterMeters}) =>
      Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracyConfig.geolocatorAccuracy,
          distanceFilter: distanceFilterMeters,
        ),
      ).map(GpsReading.fromPosition);
}

/// Abstraction over the two system-settings pages a blocked shopkeeper needs.
///
/// WHY ITS OWN INTERFACE: the location capture stack is used by widget tests
/// that must never touch a platform channel, and the callers only care that
/// "Open settings" was attempted. A test double records the call and returns
/// the result the scenario needs.
abstract class SystemSettingsOpener {
  /// This app's page in the system settings — the way back from a permanently
  /// denied location permission.
  Future<bool> openAppSettings();

  /// The DEVICE location-services page — the way back from "GPS is turned off".
  Future<bool> openLocationSettings();
}

/// Production implementation (geolocator's own settings deep links).
class PlatformSettingsOpener implements SystemSettingsOpener {
  const PlatformSettingsOpener();

  @override
  Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } catch (_) {
      return false;
    }
  }
}

/// Test double: records which page was requested, opens nothing.
class RecordingSettingsOpener implements SystemSettingsOpener {
  final List<String> calls = [];

  /// Result handed back to the caller.
  bool result = true;

  @override
  Future<bool> openAppSettings() async {
    calls.add('app');
    return result;
  }

  @override
  Future<bool> openLocationSettings() async {
    calls.add('location');
    return result;
  }
}

/// High-accuracy location service: permission flow, multi-reading acquisition,
/// best-reading selection, staleness handling — NO low-level GPS logic in UI.
class LocationService {
  LocationService({
    PositionSource? positionSource,
    SystemSettingsOpener? settingsOpener,
  })  : _source = positionSource ?? const GeolocatorPositionSource(),
        _settings = settingsOpener ?? const PlatformSettingsOpener();

  static final LocationService instance =
      LocationService();

  final PositionSource _source;
  final SystemSettingsOpener _settings;

  /// Opens this app's page in the system settings. `false` when the platform
  /// refused — the caller explains instead of pretending it worked.
  Future<bool> openAppSettings() => _settings.openAppSettings();

  /// Opens the device location-services page (GPS off, not permission).
  Future<bool> openLocationSettings() => _settings.openLocationSettings();

  /// Pre-flight permission/service check. Never throws.
  Future<LocationPermissionStatus> resolvePermission() async {
    try {
      return await _source.resolvePermission();
    } catch (_) {
      return const LocationPermissionStatus(
        serviceEnabled: false,
        permission: LocationPermission.denied,
      );
    }
  }

  /// Collects multiple readings and returns the best valid one.
  ///
  /// Stops early once the target accuracy is reached; otherwise keeps
  /// collecting until [LocationAccuracyConfig.acquisitionTimeout] and falls
  /// back to the best available reading ("Best available location found").
  Future<LocationAcquisition> acquireBestLocation({
    Duration? timeout,
    void Function(GpsReading current)? onReading,
  }) async {
    final effectiveTimeout =
        timeout ?? LocationAccuracyConfig.acquisitionTimeout;
    final readings = <GpsReading>[];
    GpsReading? best;

    debugPrint('[LOC] acquireBestLocation started (timeout: ${effectiveTimeout.inSeconds}s)');

    // STEP 1 — immediate single high-accuracy fix (fast path).
    try {
      final first = await _source
          .readOnce(timeLimit: LocationAccuracyConfig.singleReadingTimeLimit)
          .timeout(effectiveTimeout);
      readings.add(first);
      best = LocationAcquisitionEngine.bestOf(readings);
      onReading?.call(first);
      debugPrint('[LOC] STEP 1: got reading #${readings.length}, best=${best != null}');
      if (best != null && LocationAcquisitionEngine.reachedTarget(best)) {
        return LocationAcquisition(
            best: best, readings: readings, timedOut: false);
      }
    } on TimeoutException {
      debugPrint('[LOC] STEP 1: timed out');
    } catch (e) {
      debugPrint('[LOC] STEP 1: error: $e');
    }

    // STEP 2 — collect a short stream of readings and improve accuracy.
    try {
      final stream = _source
          .readStream(
              distanceFilterMeters:
                  LocationAccuracyConfig.streamDistanceFilterMeters)
          .timeout(effectiveTimeout, onTimeout: (sink) => sink.close());
      await for (final reading in stream) {
        readings.add(reading);
        best = LocationAcquisitionEngine.bestOf(readings);
        onReading?.call(reading);
        debugPrint('[LOC] STEP 2: got reading #${readings.length}, best=${best != null}');
        if (best != null && LocationAcquisitionEngine.reachedTarget(best)) {
          return LocationAcquisition(
              best: best, readings: readings, timedOut: false);
        }
      }
      debugPrint('[LOC] STEP 2: stream ended with ${readings.length} readings');
    } catch (e) {
      debugPrint('[LOC] STEP 2: error: $e');
    }

    // FALLBACK — if no clean (non-mock) readings were found, try again
    // including mock-flagged readings rather than returning nothing.
    if (best == null && readings.isNotEmpty) {
      best = LocationAcquisitionEngine.bestOf(readings, includeMock: true);
      debugPrint('[LOC] FALLBACK: using mock readings, best=${best != null}');
    }

    debugPrint('[LOC] acquireBestLocation ended: best=${best != null}, readings=${readings.length}');
    return LocationAcquisition(
      best: best,
      readings: readings,
      timedOut:
          best == null || !LocationAcquisitionEngine.reachedTarget(best),
    );
  }

  /// Distance in meters between two coordinates (Haversine via geolocator).
  double distanceBetween(double lat1, double lng1, double lat2, double lng2) =>
      Geolocator.distanceBetween(lat1, lng1, lat2, lng2);

  /// Reverse-geocode a lat/lng into a [PickedLocation] (Google → Mappls → OSM).
  /// Returns null on failure — callers must fall back to coordinates only.
  Future<PickedLocation?> reverseGeocode(double latitude, double longitude) async {
    final geocoder = GeocodingService.instance;
    final geo = await geocoder.reverseGeocode(latitude, longitude);
    if (geo == null) return null;
    return PickedLocation(
      latitude: latitude,
      longitude: longitude,
      addressLine: geo.formattedAddress,
      city: geo.city,
      state: geo.state,
      pincode: geo.pincode,
      country: 'India',
    );
  }
}