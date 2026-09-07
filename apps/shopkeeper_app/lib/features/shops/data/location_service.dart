import 'dart:async';

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
  ///   1. discard invalid coordinates, mock fixes and obviously poor readings,
  ///   2. smallest accuracy radius wins,
  ///   3. ties broken by the most recent timestamp.
  static GpsReading? bestOf(Iterable<GpsReading> readings) {
    final valid = readings
        .where((r) => r.hasValidCoordinates)
        .where((r) => !r.isMockOrUnknown)
        .where((r) =>
            r.accuracy == null ||
            r.accuracy! <= LocationAccuracyConfig.discardAboveMeters)
        .toList(growable: false);
    if (valid.isEmpty) return null;
    GpsReading best = valid.first;
    for (final r in valid.skip(1)) {
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
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return LocationPermissionStatus(
      serviceEnabled: serviceEnabled,
      permission: permission,
    );
  }

  @override
  Future<GpsReading> readOnce({Duration? timeLimit}) async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracyConfig.geolocatorAccuracy,
        timeLimit: timeLimit ?? LocationAccuracyConfig.singleReadingTimeLimit,
      ),
    );
    return GpsReading.fromPosition(position);
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

/// High-accuracy location service: permission flow, multi-reading acquisition,
/// best-reading selection, staleness handling — NO low-level GPS logic in UI.
class LocationService {
  LocationService({PositionSource? positionSource})
      : _source = positionSource ?? const GeolocatorPositionSource();

  static final LocationService instance =
      LocationService();

  final PositionSource _source;

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

    // STEP 1 — immediate single high-accuracy fix (fast path).
    try {
      final first = await _source
          .readOnce(timeLimit: LocationAccuracyConfig.singleReadingTimeLimit)
          .timeout(effectiveTimeout);
      readings.add(first);
      best = LocationAcquisitionEngine.bestOf(readings);
      onReading?.call(first);
      if (best != null && LocationAcquisitionEngine.reachedTarget(best)) {
        return LocationAcquisition(
            best: best, readings: readings, timedOut: false);
      }
    } on TimeoutException {
      // fall through to the streaming window below
    } catch (_) {
      // fall through to the streaming window below
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
        if (best != null && LocationAcquisitionEngine.reachedTarget(best)) {
          return LocationAcquisition(
              best: best, readings: readings, timedOut: false);
        }
      }
    } catch (_) {
      // stream unavailable — return whatever we have below
    }

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