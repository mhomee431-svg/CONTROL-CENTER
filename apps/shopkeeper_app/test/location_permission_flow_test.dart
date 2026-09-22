import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/data/location_service.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/location_capture_state.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/presentation/controllers/location_capture_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/presentation/screens/location_capture_screen.dart';

/// Scripted position source — no platform channels, deterministic outcomes.
class _ScriptedSource implements PositionSource {
  _ScriptedSource(this.permission, {this.serviceEnabled = true});

  final LocationPermission permission;
  final bool serviceEnabled;

  @override
  Future<LocationPermissionStatus> resolvePermission() async =>
      LocationPermissionStatus(
        serviceEnabled: serviceEnabled,
        permission: permission,
      );

  @override
  Future<GpsReading> readOnce({Duration? timeLimit}) async => _fix(8);

  @override
  Stream<GpsReading> readStream({required int distanceFilterMeters}) async* {}
}

GpsReading _fix(double accuracy) => GpsReading(
      latitude: 25.5941,
      longitude: 85.1376,
      timestamp: DateTime.now(),
      accuracy: accuracy,
    );

/// Location-permission flows for setting the shop location.
///
/// Covered here: the two system-settings escape hatches, the map-only
/// fallback ("Choose Location on Map") and the honest provenance of a
/// hand-placed pin (MANUAL, no invented accuracy).
void main() {
  LocationService serviceOf(
    LocationPermission permission, {
    bool serviceEnabled = true,
    RecordingSettingsOpener? opener,
  }) =>
      LocationService(
        positionSource: _ScriptedSource(
          permission,
          serviceEnabled: serviceEnabled,
        ),
        settingsOpener: opener ?? RecordingSettingsOpener(),
      );

  group('LocationService system-settings openers', () {
    test('both pages delegate and report a refusal honestly', () async {
      final opener = RecordingSettingsOpener();
      final service = serviceOf(LocationPermission.deniedForever, opener: opener);

      await service.openAppSettings();
      await service.openLocationSettings();
      expect(opener.calls, ['app', 'location']);

      opener.result = false;
      expect(await service.openAppSettings(), isFalse);
    });
  });

  group('LocationCaptureController map-only fallback', () {
    ProviderContainer containerOf(LocationService service) {
      final container = ProviderContainer(overrides: [
        locationServiceProvider.overrideWithValue(service),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('a denied permission sets the honest blocked state', () async {
      final container = containerOf(serviceOf(LocationPermission.deniedForever));
      await container.read(locationCaptureControllerProvider.notifier).startCapture();

      final state = container.read(locationCaptureControllerProvider);
      expect(state.status, LocationCaptureStatus.locationPermissionDenied);
      expect(state.permissionBlocked, isTrue);
      expect(state.deviceReading, isNull, reason: 'never fabricates a fix');
    });

    test('map-only mode is confirmable with a hand-placed pin, no GPS fix',
        () async {
      final container = containerOf(serviceOf(LocationPermission.denied));
      final controller = container.read(locationCaptureControllerProvider.notifier);

      controller.startMapOnlyCapture();
      var state = container.read(locationCaptureControllerProvider);
      expect(state.status, LocationCaptureStatus.locationReady);
      expect(state.mapOnly, isTrue);
      expect(state.canConfirm, isFalse, reason: 'no pin yet');

      controller.moveShopPin(const LatLng(25.6, 85.1));
      state = container.read(locationCaptureControllerProvider);
      expect(state.canConfirm, isTrue,
          reason: 'a hand-placed pin needs no GPS reading');
      expect(state.accuracyMeters, isNull);
    });

    test('confirming a map-only pin never pretends a GPS fix existed',
        () async {
      final container = containerOf(serviceOf(LocationPermission.denied));
      final controller = container.read(locationCaptureControllerProvider.notifier);

      controller.startMapOnlyCapture();
      controller.moveShopPin(const LatLng(25.6, 85.1));
      await controller.confirmLocation();

      final state = container.read(locationCaptureControllerProvider);
      expect(state.status, LocationCaptureStatus.readyForConfirmation);
      expect(state.shopPin, const LatLng(25.6, 85.1));
      expect(state.deviceReading, isNull);
      // Reverse geocoding is best-effort: with no provider reachable the
      // address is empty, never invented.
      expect(state.address?.city ?? '', isEmpty);
    });
  });

  group('LocationCaptureScreen permission states', () {
    Future<void> pumpScreen(
      WidgetTester tester,
      LocationService service,
    ) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [locationServiceProvider.overrideWithValue(service)],
        child: const MaterialApp(home: LocationCaptureScreen()),
      ));
      // Flush the initState microtask that kicks off startCapture().
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('a permanently denied permission opens the system settings',
        (tester) async {
      final opener = RecordingSettingsOpener();
      await pumpScreen(
        tester,
        serviceOf(LocationPermission.deniedForever, opener: opener),
      );

      expect(find.text('Location permission is blocked'), findsOneWidget);
      // The two fallbacks that need no permission at all.
      expect(find.text('Choose Location on Map'), findsOneWidget);
      expect(find.text('Enter Address Manually'), findsOneWidget);
      for (final step in const [
        'Open your phone Settings > Apps > Passly Business',
        'Open Permissions > Location and choose "Allow"',
        'Return to the app and tap "Allow Location" again',
      ]) {
        expect(find.text(step), findsOneWidget, reason: step);
      }

      await tester.tap(find.byKey(const Key('location_permission_primary')));
      await tester.pump();
      expect(opener.calls, ['app'],
          reason: 'the app settings page is the only way back');
    });

    testWidgets('GPS switched off sends the shopkeeper to the location page',
        (tester) async {
      final opener = RecordingSettingsOpener();
      await pumpScreen(
        tester,
        serviceOf(
          LocationPermission.whileInUse,
          serviceEnabled: false,
          opener: opener,
        ),
      );

      expect(find.textContaining('Location services are turned off'),
          findsOneWidget);
      expect(find.text('Turn On Location Services'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
      expect(find.text('Choose Location on Map'), findsOneWidget);

      await tester.tap(find.byKey(const Key('location_turn_on_gps')));
      await tester.pump();
      expect(opener.calls, ['location'],
          reason: 'the device switch lives on the location settings page');
    });

    testWidgets('"Choose Location on Map" works with no permission at all',
        (tester) async {
      await pumpScreen(tester, serviceOf(LocationPermission.denied));

      await tester.tap(find.text('Choose Location on Map'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Place your shop pin'), findsOneWidget);
      expect(find.textContaining('No GPS fix'), findsOneWidget);
      // The map card AND the hint snackbar both say it.
      expect(
          find.textContaining('Tap the map to place your shop pin'),
          findsWidgets);
      // No GPS fix exists, so none is claimed.
      expect(find.textContaining('Accuracy: '), findsNothing);

      // Let the hint snackbar time out so no timer outlives the test.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  group('CapturedShopLocation provenance', () {
    test('a GPS fix reports GPS with its REAL accuracy radius', () {
      final captured = CapturedShopLocation(
        latitude: 25.5941,
        longitude: 85.1376,
        accuracyMeters: 7,
        capturedAt: DateTime.utc(2026, 1, 1),
      );
      final meta = captured.toLocationMeta();
      expect(meta['location_source'], 'GPS');
      expect(meta['accuracy_meters'], 7);
      expect(meta['location_type'], 'SHOP_ENTRANCE');
    });

    test('a hand-placed pin reports MANUAL and claims no accuracy', () {
      final captured = CapturedShopLocation(
        latitude: 25.6,
        longitude: 85.1,
        capturedAt: DateTime.utc(2026, 1, 1),
        locationSource: 'MANUAL',
        integrityStatus: 'UNKNOWN',
      );
      final meta = captured.toLocationMeta();
      expect(meta['location_source'], 'MANUAL');
      expect(meta.containsKey('accuracy_meters'), isFalse,
          reason: 'no fix → no accuracy, never 0 m');
      expect(meta['location_integrity_status'], 'UNKNOWN');
    });
  });
}
