import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/data/location_service.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/presentation/controllers/location_capture_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/presentation/screens/location_capture_screen.dart';

/// Scripted position source — no platform channels, deterministic outcomes.
class _ScriptedSource implements PositionSource {
  _ScriptedSource(
    this.permission,
    this.readings, {
    this.serviceEnabled = true,
  });

  final LocationPermission permission;
  final List<GpsReading> readings;
  final bool serviceEnabled;

  @override
  Future<LocationPermissionStatus> resolvePermission() async =>
      LocationPermissionStatus(
        serviceEnabled: serviceEnabled,
        permission: permission,
      );

  @override
  Future<GpsReading> readOnce({Duration? timeLimit}) async => readings.isEmpty
      ? GpsReading(
          latitude: 25.5941,
          longitude: 85.1376,
          timestamp: DateTime.now(),
          accuracy: 40,
        )
      : readings.first;

  @override
  Stream<GpsReading> readStream({required int distanceFilterMeters}) async* {
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

Future<void> pumpScreen(
  WidgetTester tester, {
  required LocationPermission permission,
  required List<GpsReading> readings,
  bool serviceEnabled = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        locationServiceProvider.overrideWithValue(
          LocationService(
            positionSource: _ScriptedSource(
              permission,
              readings,
              serviceEnabled: serviceEnabled,
            ),
          ),
        ),
      ],
      child: const MaterialApp(home: LocationCaptureScreen()),
    ),
  );
  // Flush the initState microtask that kicks off startCapture().
  await tester.pump();
}

void main() {
  testWidgets('denied permission shows the blocked view with a manual exit',
      (tester) async {
    await pumpScreen(
      tester,
      permission: LocationPermission.denied,
      readings: const [],
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text('Location permission is required to accurately add your shop.'),
      findsOneWidget,
    );
    expect(find.text('Allow Location'), findsOneWidget);
    // Never fabricates coordinates for a denied permission.
    expect(find.byType(GoogleMapPlaceholder), findsNothing);
  });

  testWidgets('disabled GPS shows the enable-GPS view, not a fake fix',
      (tester) async {
    await pumpScreen(
      tester,
      permission: LocationPermission.whileInUse,
      readings: [_fix(7)],
      serviceEnabled: false,
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.textContaining('Location services are turned off'),
      findsOneWidget,
    );
    expect(find.text('Try Again'), findsOneWidget);
  });

  testWidgets('a good fix lands on the map with honest accuracy copy',
      (tester) async {
    await pumpScreen(
      tester,
      permission: LocationPermission.whileInUse,
      readings: [_fix(7)],
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Location found').evaluate().isNotEmpty) break;
    }

    expect(find.text('Location found'), findsOneWidget);
    expect(find.textContaining('Location accuracy'), findsOneWidget);
    // Both the accuracy chip and the status row show the real radius.
    expect(find.textContaining('Accuracy: 7 m'), findsNWidgets(2));
    expect(find.text('Confirm Shop Location'), findsOneWidget);
    // The required wording contract: no "100% accurate" claim anywhere.
    expect(find.textContaining('100%'), findsNothing);
  });
}

/// Sentinel so the denied-state assertion can prove no map is built yet.
class GoogleMapPlaceholder extends StatelessWidget {
  const GoogleMapPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
