import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/features/location/domain/models/user_location.dart';

/// Accuracy honesty: the app must never claim a precision the device did not
/// report.
void main() {
  UserLocation build({double accuracy = 0, bool approximate = false}) =>
      UserLocation(
        latitude: 12.9716,
        longitude: 77.5946,
        accuracyMeters: accuracy,
        isApproximate: approximate,
      );

  group('accuracy reporting', () {
    test('a missing accuracy is reported as unknown, never as exact', () {
      final location = build();
      expect(location.hasReportedAccuracy, isFalse);
      expect(location.isLowAccuracy, isFalse);
      expect(location.accuracySummary, isNot(contains('Accurate')));
    });

    test('a good fix is summarised with a tilde, not as exact', () {
      final location = build(accuracy: 12);
      expect(location.isLowAccuracy, isFalse);
      expect(location.accuracySummary, 'Accurate to ~12 m');
      expect(location.accuracySummary, isNot(contains('exact')));
    });

    test('a coarse fix is labelled approximate', () {
      final location = build(accuracy: 850);
      expect(location.isLowAccuracy, isTrue);
      expect(location.accuracySummary, 'Approximate (~850 m)');
    });

    test('kilometre-scale accuracy is readable', () {
      expect(build(accuracy: 2400).accuracySummary, 'Approximate (~2.4 km)');
    });

    test('an unusable fix is flagged separately', () {
      expect(build(accuracy: 5000).isUnusableAccuracy, isTrue);
      expect(build(accuracy: 20).isUnusableAccuracy, isFalse);
    });
  });

  group('location payload completeness', () {
    test('carries latitude, longitude, accuracy and a timestamp', () {
      final captured = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final location = UserLocation.withCapturedAt(
        latitude: 25.5941,
        longitude: 85.1376,
        accuracyMeters: 18,
        capturedAt: captured,
      );

      expect(location.latitude, 25.5941);
      expect(location.longitude, 85.1376);
      expect(location.accuracyMeters, 18);
      expect(location.capturedAtMs, 1700000000000);
      expect(location.capturedAt, isNotNull);
      expect(location.hasValidCoordinates, isTrue);
    });

    test('survives a JSON round-trip so accuracy is never lost', () {
      final original = UserLocation.withCapturedAt(
        latitude: 25.5941,
        longitude: 85.1376,
        accuracyMeters: 42,
        capturedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      final restored = UserLocation.fromJson(original.toJson());

      expect(restored.latitude, original.latitude);
      expect(restored.longitude, original.longitude);
      expect(restored.accuracyMeters, 42);
      expect(restored.capturedAtMs, original.capturedAtMs);
    });
  });
}
