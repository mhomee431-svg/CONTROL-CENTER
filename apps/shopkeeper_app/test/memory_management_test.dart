/// MEMORY MANAGEMENT (spec §111).
///
/// Pins the three resource contracts this app depends on:
///   * **repeated stream subscriptions** — a repeat GPS acquisition joins the
///     attempt already running instead of opening a second platform position
///     stream;
///   * **late callbacks** — an acquisition that finishes after the shopkeeper
///     left cannot write its fix back into the cleared state;
///   * **unbounded image caching** — a local photo preview decodes at the size
///     the widget paints, not at the camera's full resolution.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/widgets/product_image_view.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/data/location_service.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/location_capture_state.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/presentation/controllers/location_capture_controller.dart';

/// Counts how many times the platform position stream was opened, so a test
/// can prove a repeat call did NOT start a second one.
class _CountingSource implements PositionSource {
  _CountingSource(this.readings);

  final List<GpsReading> readings;

  /// Every `readStream` call — i.e. every live GPS subscription opened.
  int streamSubscriptions = 0;

  @override
  Future<LocationPermissionStatus> resolvePermission() async =>
      const LocationPermissionStatus(
        serviceEnabled: true,
        permission: LocationPermission.whileInUse,
      );

  @override
  Future<GpsReading> readOnce({Duration? timeLimit}) async => readings.isEmpty
      ? GpsReading(
          latitude: 25.5941,
          longitude: 85.1376,
          timestamp: DateTime.now(),
          accuracy: 900,
        )
      : readings.first;

  @override
  Stream<GpsReading> readStream({required int distanceFilterMeters}) async* {
    streamSubscriptions++;
    for (final reading in readings) {
      yield reading;
    }
  }
}

GpsReading _fix(double accuracy) => GpsReading(
      latitude: 25.5941,
      longitude: 85.1376,
      timestamp: DateTime.now(),
      accuracy: accuracy,
    );

void main() {
  ProviderContainer containerWith(_CountingSource source) {
    final container = ProviderContainer(overrides: [
      locationServiceProvider.overrideWithValue(
        LocationService(positionSource: source),
      ),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  group('§111 — repeated stream subscriptions (GPS)', () {
    test('a repeat acquire() joins the running attempt, not a second stream',
        () async {
      final source = _CountingSource([_fix(30)]);
      final container = containerWith(source);

      final controller =
          container.read(locationCaptureControllerProvider.notifier);
      final first = controller.acquire();
      // The double-tap: a second call while the first is still in flight.
      final second = controller.acquire();

      expect(identical(first, second), isTrue,
          reason: 'the second call must join the FIRST attempt');
      await first;

      expect(source.streamSubscriptions, 1,
          reason: 'exactly one platform position stream may be open');
      expect(controller.isAcquiring, isFalse,
          reason: 'the slot is released once the attempt completes');
    });

    test('a new acquire after completion opens a fresh stream', () async {
      final source = _CountingSource([_fix(30)]);
      final container = containerWith(source);

      final controller =
          container.read(locationCaptureControllerProvider.notifier);
      await controller.acquire();
      await controller.acquire();

      // Sequential calls are legitimate: each run gets its own subscription.
      expect(source.streamSubscriptions, 2);
    });

    test('many rapid calls still open only one stream', () async {
      final source = _CountingSource([_fix(30)]);
      final container = containerWith(source);

      final controller =
          container.read(locationCaptureControllerProvider.notifier);
      await Future.wait([for (var i = 0; i < 5; i++) controller.acquire()]);

      expect(source.streamSubscriptions, 1);
    });
  });

  group('§111 — late callbacks never resurrect a cleared fix', () {
    test('reset() drops the reading of an acquisition still in flight',
        () async {
      final source = _CountingSource([_fix(30)]);
      final container = containerWith(source);

      final controller =
          container.read(locationCaptureControllerProvider.notifier);
      final attempt = controller.acquire();
      // The shopkeeper navigated away before the fix arrived.
      controller.reset();
      await attempt;

      final state = container.read(locationCaptureControllerProvider);
      expect(state.status, LocationCaptureStatus.initial,
          reason: 'the cleared state must stay cleared');
      expect(state.deviceReading, isNull,
          reason: 'a superseded fix must not reappear as a shop pin');
      expect(state.shopPin, isNull);
    });
  });

  group('§111 — unbounded image caching', () {
    testWidgets('a local photo preview never decodes at source resolution',
        (tester) async {
      // Regression: Image.file with no cacheWidth decoded the full camera
      // bitmap (up to 2000px) for a preview box, and kept it in the image
      // cache. The widget must sample to the size it actually paints.
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(devicePixelRatio: 3),
            child: Center(
              child: ProductImageView(
                localPath: '/tmp/verification-photo.jpg',
                width: 72,
                height: 72,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // At DPR 3 a 72px box needs 216px of bitmap, not the source's 2000.
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.cacheWidth, 216);
      expect(image.cacheWidth, lessThan(1024),
          reason: 'the decode is bounded, never the full-resolution file');
    });

    testWidgets('an explicit cacheWidth still wins for a local photo',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(devicePixelRatio: 3),
            child: Center(
              child: ProductImageView(
                localPath: '/tmp/verification-photo.jpg',
                width: 72,
                height: 72,
                cacheWidth: 96,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.cacheWidth, 96);
    });

    testWidgets('the decode width is clamped to a sane range', (tester) async {
      // A zero-pixel-ratio box must never produce an invalid cacheWidth.
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(devicePixelRatio: 0.0),
            child: Center(
              child: ProductImageView(
                localPath: '/tmp/verification-photo.jpg',
                width: 72,
                height: 72,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.cacheWidth, greaterThanOrEqualTo(1));
    });
  });
}
