import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/location_repository.dart';
import '../../domain/map_service.dart';
import '../../domain/models/location_exception.dart';
import '../../domain/models/map_route.dart';
import '../../domain/models/user_location.dart';
import 'location_controller.dart';

/// Lifecycle of the pin-drop map screen.
enum MapPickerStatus {
  /// No location resolved yet (still reading cached GPS / loading).
  initial,

  /// A location (cached or fresh) is available; the map is interactive.
  ready,

  /// The pin-drop flow hit an unrecoverable error.
  error,
}

/// Immutable state for the map picker (pin-drop) screen.
class MapPickerState {
  final MapPickerStatus status;

  /// User-safe error message for the last failed action (route, geocode...).
  final String? errorMessage;

  /// The user's location (cached on entry, refreshed by a silent GPS ping).
  /// Used as the origin when drawing a driving route.
  final UserLocation? userLocation;

  /// Raw coordinates currently under the center pin.
  final MapLatLng? pinned;

  /// Reverse-geocoded address (address + pincode) of the pinned point.
  final UserLocation? pinnedAddress;

  /// True while a reverse-geocode request for the pin is in flight.
  final bool isGeocoding;

  /// True while a driving route is being fetched from the Directions API.
  final bool isRouteLoading;

  /// Decoded driving route (polyline vertices) drawn on the map when present.
  final MapRoute? route;

  const MapPickerState({
    this.status = MapPickerStatus.initial,
    this.errorMessage,
    this.userLocation,
    this.pinned,
    this.pinnedAddress,
    this.isGeocoding = false,
    this.isRouteLoading = false,
    this.route,
  });

  bool get hasPinnedPoint => pinned != null;

  /// Whether a route polyline is currently rendered on the map.
  bool get hasRoute => route != null && route!.points.isNotEmpty;

  /// Resolves the label shown in the bottom sheet: address, city, or raw
  /// coordinates while the reverse geocode is pending.
  String get addressLabel {
    final address = pinnedAddress;
    if (address != null && address.displayAddress.isNotEmpty) {
      return address.displayAddress;
    }
    if (pinned != null) {
      return '${pinned!.latitude.toStringAsFixed(4)}, '
          '${pinned!.longitude.toStringAsFixed(4)}';
    }
    return 'Move the map to choose your location';
  }

  /// The pincode of the pinned address, or `null` while unknown.
  String? get pincodeLabel {
    final address = pinnedAddress;
    if (address == null || address.pincode.isEmpty) return null;
    return address.pincode;
  }

  MapPickerState copyWith({
    MapPickerStatus? status,
    Object? errorMessage = _unset,
    UserLocation? userLocation,
    Object? pinned = _unset,
    Object? pinnedAddress = _unset,
    bool? isGeocoding,
    bool? isRouteLoading,
    Object? route = _unset,
  }) {
    return MapPickerState(
      status: status ?? this.status,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : (errorMessage as String?),
      userLocation: userLocation ?? this.userLocation,
      pinned: identical(pinned, _unset) ? this.pinned : (pinned as MapLatLng?),
      pinnedAddress: identical(pinnedAddress, _unset)
          ? this.pinnedAddress
          : (pinnedAddress as UserLocation?),
      isGeocoding: isGeocoding ?? this.isGeocoding,
      isRouteLoading: isRouteLoading ?? this.isRouteLoading,
      route: identical(route, _unset) ? this.route : (route as MapRoute?),
    );
  }
}

const _unset = Object();

/// Notifier owning the map-picker (pin-drop) flow.
///
/// Auto-disposed when [MapPickerScreen] closes.
final mapPickerControllerProvider =
    NotifierProvider.autoDispose<MapPickerController, MapPickerState>(
      MapPickerController.new,
    );

class MapPickerController extends Notifier<MapPickerState> {
  /// Debounce for reverse-geocoding while the map is dragged (avoids
  /// hammering the Geocoding API with one request per camera frame).
  static const _geocodeDebounceDuration = Duration(milliseconds: 300);

  Timer? _geocodeDebounce;
  int _geocodeRequestSeq = 0;
  UserLocation? _origin;

  /// Monotonic token for driving-route requests.
  ///
  /// The reverse geocode above already guards itself this way; the route did
  /// not, and it is the more dangerous of the two. A route request costs a
  /// Directions API call, so the customer can easily start one, move the pin,
  /// and start another. Without a token the first (older) response can land
  /// last and draw a polyline to a pin the customer has already moved away
  /// from -- a map that confidently shows the wrong route.
  int _routeRequestSeq = 0;

  /// Identity of the route currently drawn or in flight, used to skip a
  /// duplicate request for a destination the customer already asked for.
  String? _activeRouteKey;

  @override
  MapPickerState build() {
    ref.onDispose(() => _geocodeDebounce?.cancel());
    _init();
    return const MapPickerState();
  }

  /// The origin point used when drawing a driving route (cached or GPS).
  UserLocation? get origin => _origin;

  // ── Initialisation ─────────────────────────────────────────────────────

  /// Seeds the map with the cached location instantly, then silently nudges
  /// GPS in the background to refresh it. The map is never blocked waiting.
  Future<void> _init() async {
    var start = ref.read(locationControllerProvider).location;
    if (start == null || !start.hasValidCoordinates) {
      try {
        start = await ref
            .read(locationRepositoryProvider)
            .getLastKnownLocation();
      } catch (_) {
        start = null;
      }
    }
    if (start != null && start.hasValidCoordinates) {
      _origin = start;
      state = MapPickerState(
        status: MapPickerStatus.ready,
        userLocation: start,
      );
    }
    // Best-effort; every failure is swallowed so the screen still works
    // with the cached location.
    unawaited(_silentGpsPing());
  }

  Future<void> _silentGpsPing() async {
    try {
      final locationController = ref.read(locationControllerProvider.notifier);
      await locationController.fetchCurrentLocation(force: false);
      if (!ref.mounted) return;
      final fresh = ref.read(locationControllerProvider).location;
      if (fresh != null && fresh.hasValidCoordinates) {
        _origin = fresh;
        state = state.copyWith(
          status: MapPickerStatus.ready,
          userLocation: fresh,
        );
      }
    } catch (_) {
      // Cached location remains active; nothing to surface.
    }
  }

  // ── Pin movement ───────────────────────────────────────────────────────

  /// Called from `onCameraIdle`: re-seats the pin under the new camera
  /// center and schedules a (debounced) reverse geocode.
  void onPinMoved(MapLatLng point) {
    _geocodeDebounce?.cancel();
    _geocodeRequestSeq++;
    // The pin the in-flight route was heading for no longer exists. Bumping the
    // token makes that response a no-op when it arrives, so the customer can
    // never end up looking at a route to where the pin used to be.
    _routeRequestSeq++;
    _activeRouteKey = null;
    state = state.copyWith(
      pinned: point,
      pinnedAddress: null,
      route: null,
      errorMessage: null,
    );
    _geocodeDebounce = Timer(
      _geocodeDebounceDuration,
      () => _reverseGeocode(point),
    );
  }

  Future<void> _reverseGeocode(MapLatLng point) async {
    final requestSeq = ++_geocodeRequestSeq;
    state = state.copyWith(isGeocoding: true);
    try {
      final address = await ref
          .read(mapServiceProvider)
          .reverseGeocode(latitude: point.latitude, longitude: point.longitude);
      if (!ref.mounted || requestSeq != _geocodeRequestSeq) return;
      state = state.copyWith(isGeocoding: false, pinnedAddress: address);
    } on LocationException catch (e) {
      if (!ref.mounted || requestSeq != _geocodeRequestSeq) return;
      state = state.copyWith(isGeocoding: false, errorMessage: e.message);
    } catch (_) {
      if (!ref.mounted || requestSeq != _geocodeRequestSeq) return;
      state = state.copyWith(isGeocoding: false);
    }
  }

  // ── Directions ─────────────────────────────────────────────────────────

  /// Draws a driving-route polyline from the user's location to the pin.
  Future<void> loadDrivingRoute() async {
    final pinned = state.pinned;
    final origin = _origin ?? state.userLocation;
    if (pinned == null) return;
    if (origin == null) {
      state = state.copyWith(
        errorMessage: 'Could not determine your current location.',
      );
      return;
    }

    // Tapping "route" twice for the same destination is one request, not two.
    // This is the cheap case the sequence token cannot catch on its own: the
    // second call would supersede the first, and the first response would then
    // be thrown away, wasting a paid Directions call to draw the same line.
    final routeKey =
        '${origin.latitude},${origin.longitude}'
        '->${pinned.latitude},${pinned.longitude}';
    if (routeKey == _activeRouteKey && !state.isRouteLoading) return;
    final requestSeq = ++_routeRequestSeq;
    _activeRouteKey = routeKey;

    state = state.copyWith(
      isRouteLoading: true,
      route: null,
      errorMessage: null,
    );
    try {
      final route = await ref
          .read(mapServiceProvider)
          .fetchDrivingRoute(
            origin: MapLatLng(origin.latitude, origin.longitude),
            destination: pinned,
          );
      if (!ref.mounted || requestSeq != _routeRequestSeq) return;
      state = state.copyWith(isRouteLoading: false, route: route);
    } on LocationException catch (e) {
      if (!ref.mounted || requestSeq != _routeRequestSeq) return;
      _activeRouteKey = null;
      state = state.copyWith(isRouteLoading: false, errorMessage: e.message);
    } catch (_) {
      if (!ref.mounted || requestSeq != _routeRequestSeq) return;
      _activeRouteKey = null;
      state = state.copyWith(
        isRouteLoading: false,
        errorMessage: 'Could not fetch the route.',
      );
    }
  }

  /// Removes the drawn route polyline.
  void clearRoute() {
    // Forget the key too, otherwise asking for this exact route again is
    // treated as a duplicate of a route the customer just dismissed.
    _activeRouteKey = null;
    state = state.copyWith(route: null, errorMessage: null);
  }

  /// Opens the native Google Maps app pointed at the pinned destination
  /// (google.navigation URI scheme; web fallback handled by the service).
  Future<void> launchNavigation() async {
    final pinned = state.pinned;
    if (pinned == null) return;
    try {
      final launched = await ref
          .read(mapServiceProvider)
          .launchNavigation(
            destination: pinned,
            label: state.pinnedAddress?.label,
          );
      if (!launched && ref.mounted) {
        state = state.copyWith(
          errorMessage: 'No navigation app available on this device.',
        );
      }
    } catch (_) {
      if (ref.mounted) {
        state = state.copyWith(errorMessage: 'Could not open navigation.');
      }
    }
  }

  // ── Confirmation ───────────────────────────────────────────────────────

  /// Persists the pinned (reverse-geocoded) location as the active one via
  /// [LocationController.setManualLocation].
  Future<void> confirmLocation() async {
    final pinned = state.pinned;
    if (pinned == null) return;
    final address =
        state.pinnedAddress ??
        UserLocation(
          latitude: pinned.latitude,
          longitude: pinned.longitude,
          address: 'Selected on map',
          label: 'Pinned location',
          isManual: true,
        );
    await ref
        .read(locationControllerProvider.notifier)
        .setManualLocation(address.copyWith(isManual: true));
  }
}
