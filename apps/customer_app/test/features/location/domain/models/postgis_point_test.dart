import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/features/location/domain/models/postgis_point.dart';
import 'package:hyperlocal_app/features/location/domain/models/user_location.dart';

void main() {
  group('PostGisPoint', () {
    const point = PostGisPoint(latitude: 25.5941, longitude: 85.1376);

    test('toWkt returns POINT(lng lat) format', () {
      expect(point.toWkt(), 'POINT(85.1376 25.5941)');
    });

    test('toGeoJson returns GeoJSON Point with [lng, lat] order', () {
      expect(point.toGeoJson(), {
        'type': 'Point',
        'coordinates': [85.1376, 25.5941],
      });
    });

    test('toQueryParams returns lat/lng params', () {
      expect(point.toQueryParams(), {'lat': 25.5941, 'lng': 85.1376});
    });

    test('isValid returns true for real-world coordinates', () {
      expect(point.isValid, isTrue);
    });

    test('isValid returns false for out-of-bounds coordinates', () {
      const invalid = PostGisPoint(latitude: 95.0, longitude: 200.0);
      expect(invalid.isValid, isFalse);
    });

    test('equality works', () {
      const same = PostGisPoint(latitude: 25.5941, longitude: 85.1376);
      const different = PostGisPoint(latitude: 24.7914, longitude: 85.0002);
      expect(point, same);
      expect(point, isNot(different));
    });
  });

  group('UserLocation', () {
    const location = UserLocation(
      latitude: 25.5941,
      longitude: 85.1376,
      address: 'Patna Center',
      city: 'Patna',
      state: 'Bihar',
      pincode: '800001',
      label: 'Patna',
    );

    test('postgis returns PostGisPoint with same coords', () {
      expect(location.postgis.latitude, 25.5941);
      expect(location.postgis.longitude, 85.1376);
      expect(location.postgis.toWkt(), 'POINT(85.1376 25.5941)');
    });

    test('hasValidCoordinates returns true for valid coords', () {
      expect(location.hasValidCoordinates, isTrue);
    });

    test('isValidLocation returns true when not approximate', () {
      expect(location.isValidLocation, isTrue);
    });

    test('isValidLocation returns false when approximate', () {
      const approximate = UserLocation(
        latitude: 25.5941,
        longitude: 85.1376,
        isApproximate: true,
      );
      expect(approximate.isValidLocation, isFalse);
    });

    test('displayLabel falls back to city when label empty', () {
      const noLabel = UserLocation(
        latitude: 25.5941,
        longitude: 85.1376,
        city: 'Patna',
      );
      expect(noLabel.displayLabel, 'Patna');
    });

    test('displayLabel falls back to Unknown when both empty', () {
      const empty = UserLocation(latitude: 25.5941, longitude: 85.1376);
      expect(empty.displayLabel, 'Unknown');
    });

    test('displayAddress joins non-empty parts', () {
      expect(location.displayAddress, 'Patna Center, Patna, Bihar, 800001');
    });

    test('select() marks location as selected', () {
      final selected = location.select();
      expect(selected.isSelected, isTrue);
    });

    test('withCapturedAt sets capturedAtMs', () {
      final captured = UserLocation.withCapturedAt(
        latitude: 25.5941,
        longitude: 85.1376,
        capturedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(captured.capturedAtMs, 1700000000000);
      expect(captured.capturedAt, DateTime.fromMillisecondsSinceEpoch(1700000000000));
    });

    test('JSON round-trip preserves new fields', () {
      final json = location.toJson();
      final restored = UserLocation.fromJson(json);
      expect(restored, location);
      expect(restored.label, 'Patna');
      expect(restored.isApproximate, isFalse);
      expect(restored.isSelected, isFalse);
    });
  });
}