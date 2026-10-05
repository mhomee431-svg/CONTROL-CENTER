import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/features/location/domain/location_repository.dart';
import 'package:hyperlocal_app/features/location/domain/map_service.dart';
import 'package:hyperlocal_app/features/location/domain/models/location_permission_status.dart';
import 'package:hyperlocal_app/features/location/domain/models/map_route.dart';
import 'package:hyperlocal_app/features/location/domain/models/user_location.dart';
import 'package:hyperlocal_app/features/location/presentation/controllers/map_picker_controller.dart';

const _origin = UserLocation(
  latitude: 25.5941,
  longitude: 85.1376,
  address: 'Patna',
  city: 'Patna',
  state: 'Bihar',
  pincode: '800001',
  label: 'Patna',
);

const _pinA = MapLatLng(25.60, 85.14);
const _pinB = MapLatLng(25.70, 85.20);
const _originPoint = MapLatLng(25.5941, 85.1376);

/// A Directions API stand-in whose responses can be released out of order.
///
/// Releasing the OLDEST request last is the whole point: it reproduces the real
/// failure, where a request started first comes back after one started later and
/// would otherwise draw over the newer answer.
class _GatedMapService implements MapService {
  /// One completer per in-flight route request, oldest first.
  final List<Completer<MapRoute>> gates = [];

  /// Every destination asked for, in order.
  final List<MapLatLng> destinations = [];

  @override
  Future<MapRoute> fetchDrivingRoute({
    required MapLatLng origin,
    required MapLatLng destination,
  }) {
    destinations.add(destination);
    final gate = Completer<MapRoute>();
    gates.add(gate);
    return gate.future;
  }

  /// Completes the oldest open request with a route ending at [destination].
  void releaseOldest(MapLatLng destination) => _releaseAt(0, destination);

  /// Completes the NEWEST open request, i.e. the one the customer asked for
  /// most recently. Releasing this first and the oldest second is how a test
  /// reproduces the real failure: the newer answer lands, then the older one
  /// arrives late and tries to overwrite it.
  void releaseNewest(MapLatLng destination) =>
      _releaseAt(gates.length - 1, destination);

  void _releaseAt(int index, MapLatLng destination) {
    gates
        .removeAt(index)
        .complete(
          MapRoute(
            points: [_originPoint, destination],
            distanceKm: 3,
            durationMinutes: 12,
          ),
        );
  }

  @override
  Future<UserLocation> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async => _origin;

  @override
  Future<bool> launchNavigation({
    required MapLatLng destination,
    String? label,
  }) async => true;
}

class _StubLocationRepository implements LocationRepository {
  @override
  Future<UserLocation?> getLastKnownLocation() async => _origin;

  @override
  Future<UserLocation> getCurrentLocation() async => _origin;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermissionStatus> checkPermission() async =>
      LocationPermissionStatus.granted;

  @override
  Future<LocationPermissionStatus> requestPermission() async =>
      LocationPermissionStatus.granted;

  @override
  Future<void> openLocationSettings() async {}

  @override
  Future<List<UserLocation>> searchManualLocations(String query) async =>
      const <UserLocation>[];
}

/// Boots the map picker with fakes and waits for its async `_init()` to resolve
/// the origin.
///
/// The wait is not optional: `build()` kicks off an async location lookup, and a
/// route requested before it settles has no origin to draw from. Testing that
/// window by accident would make every assertion below meaningless.
/// Waits for the picker's async `_init()` to resolve the origin.
///
/// The wait is not optional: `build()` kicks off an async location lookup, and a
/// route requested before that settles has no origin to draw from. Testing that
/// window by accident would make every assertion below meaningless.
Future<MapPickerController> _readyPicker(ProviderContainer container) async {
  final subscription = container.listen(
    mapPickerControllerProvider,
    (previous, next) {},
    fireImmediately: true,
  );
  addTearDown(subscription.close);
  for (var i = 0; i < 50; i++) {
    if (container.read(mapPickerControllerProvider).userLocation != null) break;
    await Future<void>.delayed(Duration.zero);
  }
  return container.read(mapPickerControllerProvider.notifier);
}

ProviderContainer _boot(_GatedMapService mapService) {
  FlutterSecureStorage.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      mapServiceProvider.overrideWithValue(mapService),
      locationRepositoryProvider.overrideWithValue(_StubLocationRepository()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('driving route requests', () {
    test(
      'a route for a pin the customer moved away from is discarded',
      () async {
        final mapService = _GatedMapService();
        final container = _boot(mapService);
        final controller = await _readyPicker(container);

        controller.onPinMoved(_pinA);
        final first = controller.loadDrivingRoute();
        await Future<void>.delayed(Duration.zero);
        expect(mapService.destinations, [_pinA]);

        // The customer drags the map while that request is still open.
        controller.onPinMoved(_pinB);
        await Future<void>.delayed(Duration.zero);

        // The A response now lands, and it must not be drawn.
        mapService.releaseOldest(_pinA);
        await first;

        final state = container.read(mapPickerControllerProvider);
        expect(
          state.route,
          isNull,
          reason: 'a route to the old pin must never be drawn',
        );
      },
    );

    test('the newest route wins when two are in flight', () async {
      final mapService = _GatedMapService();
      final container = _boot(mapService);
      final controller = await _readyPicker(container);

      controller.onPinMoved(_pinA);
      final first = controller.loadDrivingRoute();
      await Future<void>.delayed(Duration.zero);

      controller.onPinMoved(_pinB);
      final second = controller.loadDrivingRoute();
      await Future<void>.delayed(Duration.zero);
      expect(mapService.destinations, [_pinA, _pinB]);

      // Newest answers first, then the older one arrives late.
      mapService.releaseNewest(_pinB);
      await second;
      mapService.releaseOldest(_pinA);
      await first;

      final state = container.read(mapPickerControllerProvider);
      expect(state.route, isNotNull);
      expect(
        state.route!.points.last,
        _pinB,
        reason: 'the route must end at the pin the customer actually chose',
      );
    });

    test(
      'asking twice for the same route issues one Directions call',
      () async {
        final mapService = _GatedMapService();
        final container = _boot(mapService);
        final controller = await _readyPicker(container);

        controller.onPinMoved(_pinA);
        final first = controller.loadDrivingRoute();
        await Future<void>.delayed(Duration.zero);
        mapService.releaseOldest(_pinA);
        await first;

        final callsAfterFirst = mapService.destinations.length;

        // The customer taps the route button again for the same pin.
        await controller.loadDrivingRoute();
        await Future<void>.delayed(Duration.zero);

        expect(
          mapService.destinations.length,
          callsAfterFirst,
          reason: 'an identical route must not cost a second Directions call',
        );
        expect(container.read(mapPickerControllerProvider).route, isNotNull);
      },
    );

    test('clearing the route lets the same route be requested again', () async {
      final mapService = _GatedMapService();
      final container = _boot(mapService);
      final controller = await _readyPicker(container);

      controller.onPinMoved(_pinA);
      final first = controller.loadDrivingRoute();
      await Future<void>.delayed(Duration.zero);
      mapService.releaseOldest(_pinA);
      await first;

      controller.clearRoute();
      expect(container.read(mapPickerControllerProvider).route, isNull);

      final second = controller.loadDrivingRoute();
      await Future<void>.delayed(Duration.zero);
      expect(mapService.destinations.length, 2);
      mapService.releaseOldest(_pinA);
      await second;
      expect(container.read(mapPickerControllerProvider).route, isNotNull);
    });

    test('a route to a new pin is requested again after clearing', () async {
      final mapService = _GatedMapService();
      final container = _boot(mapService);
      final controller = await _readyPicker(container);

      controller.onPinMoved(_pinA);
      final first = controller.loadDrivingRoute();
      await Future<void>.delayed(Duration.zero);
      mapService.releaseOldest(_pinA);
      await first;

      controller.clearRoute();
      controller.onPinMoved(_pinB);
      final second = controller.loadDrivingRoute();
      await Future<void>.delayed(Duration.zero);

      expect(mapService.destinations.last, _pinB);
      mapService.releaseOldest(_pinB);
      await second;
      expect(
        container.read(mapPickerControllerProvider).route!.points.last,
        _pinB,
      );
    });
  });
}
