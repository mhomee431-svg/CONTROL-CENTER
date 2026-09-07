import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/data/location_accuracy_config.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/data/location_service.dart';

void main() {
  group('LocationAccuracyConfig', () {
    test('classifies accuracy tiers correctly', () {
      expect(LocationAccuracyConfig.tierFor(3), AccuracyTier.excellent);
      expect(LocationAccuracyConfig.tierFor(8), AccuracyTier.good);
      expect(LocationAccuracyConfig.tierFor(18), AccuracyTier.acceptable);
      expect(LocationAccuracyConfig.tierFor(40), AccuracyTier.weak);
      expect(LocationAccuracyConfig.tierFor(80), AccuracyTier.poor);
      expect(LocationAccuracyConfig.tierFor(null), AccuracyTier.unknown);
      expect(LocationAccuracyConfig.tierFor(-1), AccuracyTier.unknown);
    });
    test('never claims 100pct accurate shows real radius', () {
      expect(LocationAccuracyConfig.accuracyLabel(7), 'Accuracy: 7 m');
      expect(LocationAccuracyConfig.accuracyLabel(null), 'Accuracy unknown');
      expect(LocationAccuracyConfig.tierLabel(AccuracyTier.excellent), 'Excellent');
    });
    test('staleness uses configurable max age', () {
      final now = DateTime(2026, 9, 6, 12, 0);
      final fresh = now.subtract(const Duration(seconds: 10));
      final stale = now.subtract(const Duration(seconds: 60));
      expect(LocationAccuracyConfig.isStale(fresh, now: now), isFalse);
      expect(LocationAccuracyConfig.isStale(stale, now: now), isTrue);
    });
    test('thresholds are configurable and ordered', () {
      expect(LocationAccuracyConfig.excellentMaxMeters, lessThan(LocationAccuracyConfig.goodMaxMeters));
      expect(LocationAccuracyConfig.goodMaxMeters, lessThan(LocationAccuracyConfig.acceptableMaxMeters));
      expect(LocationAccuracyConfig.targetAccuracyMeters, lessThanOrEqualTo(LocationAccuracyConfig.minimumUsableAccuracyMeters));
    });
  });

  group('LocationAcquisitionEngine', () {
    final baseTime = DateTime(2026, 9, 6, 12, 0);
    GpsReading r(double lat, double lng, double? acc, [DateTime? time]) =>
        GpsReading(latitude: lat, longitude: lng, timestamp: time ?? baseTime, accuracy: acc);
    test('selects smallest accuracy radius', () {
      final best = LocationAcquisitionEngine.bestOf([r(10, 20, 25), r(10, 20, 8), r(10, 20, 15)]);
      expect(best!.accuracy, 8);
    });
    test('breaks ties by most recent timestamp', () {
      final best = LocationAcquisitionEngine.bestOf([r(10, 20, 10, baseTime.subtract(const Duration(seconds: 5))), r(10, 20, 10, baseTime)]);
      expect(best!.timestamp, baseTime);
    });
    test('discards invalid coordinates', () {
      final best = LocationAcquisitionEngine.bestOf([r(200, 20, 5), r(10, 20, 12)]);
      expect(best!.latitude, 10);
    });
    test('discards mock fixes', () {
      final best = LocationAcquisitionEngine.bestOf([GpsReading(latitude: 10, longitude: 20, timestamp: baseTime, accuracy: 3, isMock: true), r(10, 20, 20)]);
      expect(best!.accuracy, 20);
    });
    test('discards obviously poor readings', () {
      final best = LocationAcquisitionEngine.bestOf([r(10, 20, 200), r(10, 20, 45)]);
      expect(best!.accuracy, 45);
    });
    test('returns null when nothing valid', () {
      expect(LocationAcquisitionEngine.bestOf([]), isNull);
      expect(LocationAcquisitionEngine.bestOf([r(999, 20, 5)]), isNull);
    });
    test('reachedTarget within target accuracy', () {
      expect(LocationAcquisitionEngine.reachedTarget(r(10, 20, 8)), isTrue);
      expect(LocationAcquisitionEngine.reachedTarget(r(10, 20, 15)), isFalse);
    });
  });

group('LocationService with fake PositionSource', () {
    late FakePositionSource fake;
    late LocationService service;
    setUp(() {
      fake = FakePositionSource();
      service = LocationService(positionSource: fake);
    });

    test('resolvePermission maps deniedForever', () async {
      fake.permissionResult = const LocationPermissionStatus(serviceEnabled: true, permission: LocationPermission.deniedForever);
      final status = await service.resolvePermission();
      expect(status.deniedForever, isTrue);
      expect(status.granted, isFalse);
    });
    test('resolvePermission maps granted', () async {
      fake.permissionResult = const LocationPermissionStatus(serviceEnabled: true, permission: LocationPermission.whileInUse);
      final status = await service.resolvePermission();
      expect(status.granted, isTrue);
    });
    test('resolvePermission never throws', () async {
      fake.permissionError = true;
      final status = await service.resolvePermission();
      expect(status.granted, isFalse);
      expect(status.serviceEnabled, isFalse);
    });
    test('acquireBestLocation returns best reading', () async {
      fake.readings = [
        [GpsReading(latitude: 10, longitude: 20, timestamp: DateTime.now(), accuracy: 25)],
        [GpsReading(latitude: 10, longitude: 20, timestamp: DateTime.now(), accuracy: 25), GpsReading(latitude: 10, longitude: 20, timestamp: DateTime.now(), accuracy: 6)],
      ];
      final result = await service.acquireBestLocation(timeout: const Duration(milliseconds: 50));
      expect(result.hasUsableLocation, isTrue);
      expect(result.best!.accuracy, 6);
    });
    test('acquireBestLocation times out gracefully', () async {
      fake.readings = [];
      fake.streamDelay = const Duration(seconds: 1);
      final result = await service.acquireBestLocation(timeout: const Duration(milliseconds: 30));
      expect(result.timedOut, isTrue);
    });
  });
}

class FakePositionSource implements PositionSource {
  LocationPermissionStatus permissionResult = const LocationPermissionStatus(serviceEnabled: true, permission: LocationPermission.whileInUse);
  bool permissionError = false;
  List<List<GpsReading>> readings = [];
  Duration streamDelay = Duration.zero;

  @override
  Future<LocationPermissionStatus> resolvePermission() async {
    if (permissionError) throw Exception('boom');
    return permissionResult;
  }
  @override
  Future<GpsReading> readOnce({Duration? timeLimit}) async {
    if (readings.isEmpty) return GpsReading(latitude: 10, longitude: 20, timestamp: DateTime.now(), accuracy: 40);
    return readings.first.first;
  }
  @override
  Stream<GpsReading> readStream({required int distanceFilterMeters}) async* {
    if (streamDelay > Duration.zero) { await Future.delayed(streamDelay); return; }
    for (final batch in readings) { for (final r in batch) { yield r; } }
  }
}