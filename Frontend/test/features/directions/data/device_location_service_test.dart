import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_customer_app/features/directions/data/device_location_service.dart';
import 'package:hyperlocal_customer_app/features/directions/domain/models/location_models.dart';

void main() {
  group('DeviceLocationService.calculateDistance', () {
    final service = DeviceLocationService();

    const patna = Coordinates(25.5941, 85.1376);
    const gaya = Coordinates(24.7914, 85.0002);
    const delhi = Coordinates(28.7041, 77.1025);

    test('returns zero for identical points', () {
      expect(service.calculateDistance(patna, patna), 0.0);
    });

    test('Patna → Gaya distances to a plausible great-circle value', () {
      final km = service.calculateDistance(patna, gaya);
      expect(km, greaterThan(80));
      expect(km, lessThan(130));
    });

    test('Patna → Delhi distances to a plausible great-circle value', () {
      final km = service.calculateDistance(patna, delhi);
      expect(km, greaterThan(800));
      expect(km, lessThan(950));
    });

    test('distance is symmetric', () {
      final a = service.calculateDistance(patna, delhi);
      final b = service.calculateDistance(delhi, patna);
      expect(a, closeTo(b, 1e-9));
    });
  });

  group('DeviceLocationService mock GPS control', () {
    final service = DeviceLocationService();

    test('respects simulated GPS-disabled state', () async {
      service.setMockGpsEnabled(false);
      expect(await service.isGpsEnabled(), isFalse);
      service.setMockGpsEnabled(true);
      expect(await service.isGpsEnabled(), isTrue);
    });

    test('respects simulated permission-denied state', () async {
      service.setMockPermissionGranted(false);
      expect(await service.requestPermission(), isFalse);
      service.setMockPermissionGranted(true);
      expect(await service.requestPermission(), isTrue);
    });

    test('throws a noGps error with GPS disabled', () async {
      service.setMockGpsEnabled(false);
      expect(
        () => service.getCurrentLocation(),
        throwsA(
          isA<LocationException>().having(
            (e) => e.type,
            'type',
            LocationErrorType.noGps,
          ),
        ),
      );
    });
  });
}