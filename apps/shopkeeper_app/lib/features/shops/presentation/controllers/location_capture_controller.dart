import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../data/geocoding_service.dart';
import '../../data/location_accuracy_config.dart';
import '../../data/location_service.dart';
import '../../domain/location_capture_state.dart';

/// Injectable location service (tests override with a fake position source).
final locationServiceProvider =
    Provider<LocationService>((ref) => LocationService());

/// Injectable geocoder (provider order: Google → Mappls → OSM).
final geocodingServiceProvider =
    Provider<GeocodingService>((ref) => GeocodingService.instance);

final locationCaptureControllerProvider =
    NotifierProvider<LocationCaptureController, LocationCaptureState>(
        LocationCaptureController.new);

/// Drives the shop-location capture state machine.
///
/// The UI never talks to geolocator directly: it calls [startCapture],
/// observes [LocationCaptureState], adjusts the pin and finally confirms.
class LocationCaptureController extends Notifier<LocationCaptureState> {
  @override
  LocationCaptureState build() => const LocationCaptureState();

  LocationService get _location => ref.read(locationServiceProvider);
  GeocodingService get _geocoder => ref.read(geocodingServiceProvider);

  /// The acquisition currently in flight, or null.
  ///
  /// Every acquisition opens its OWN platform position stream (and the
  /// multi-reading path holds it open for up to the acquisition timeout). This
  /// screen has five entry points into `startCapture` / `acquire` — mount, the
  /// three retry buttons and `refreshIfStale` — so without this a double tap
  /// leaves TWO position streams running: the GPS radio stays awake for both
  /// and each completion writes state the other has already superseded (§111
  /// "repeated stream subscriptions"). A repeat call now JOINS the attempt
  /// already running instead of starting a second one.
  Future<void>? _inFlight;

  /// Identifies the current attempt. Bumped by every new acquisition and by
  /// [reset], so a completion that arrives after the shopkeeper has left the
  /// screen can never resurrect the old fix into the fresh state.
  int _generation = 0;

  /// Pre-flight: location service enabled? permission granted?
  /// Never crashes and never fabricates coordinates.
  Future<void> startCapture() async {
    state = const LocationCaptureState(
        status: LocationCaptureStatus.requestingPermission);
    final permission = await _location.resolvePermission();
    if (!permission.granted) {
      state = LocationCaptureState(
        status: LocationCaptureStatus.locationPermissionDenied,
        permission: permission,
      );
      return;
    }
    if (!permission.serviceEnabled) {
      state = LocationCaptureState(
        status: LocationCaptureStatus.locationServiceDisabled,
        permission: permission,
      );
      return;
    }
    await acquire();
  }

  /// Multi-reading acquisition with progressive accuracy feedback.
  ///
  /// Re-entrant: a call made while an acquisition is already running joins that
  /// attempt instead of opening a second platform position stream (see
  /// [_inFlight]).
  Future<void> acquire() {
    final running = _inFlight;
    if (running != null) return running;
    // `late final` so the cleanup callback can identify THIS attempt without
    // capturing a variable that has not been declared yet.
    late final Future<void> attempt;
    attempt = _runAcquire().whenComplete(() {
      if (identical(_inFlight, attempt)) _inFlight = null;
    });
    _inFlight = attempt;
    return attempt;
  }

  /// True while an acquisition is running — asserted in tests to prove a repeat
  /// call did not open a second platform position stream.
  @visibleForTesting
  bool get isAcquiring => _inFlight != null;

  Future<void> _runAcquire() async {
    final generation = ++_generation;
    state = state.copyWith(
      status: LocationCaptureStatus.fetchingLocation,
      clearError: true,
    );
    final acquisition = await _location.acquireBestLocation(
      onReading: (reading) {
        // Superseded (or the shopkeeper left): the late reading belongs to an
        // attempt nobody is watching any more.
        if (generation != _generation) return;
        // Update ONLY the accuracy indicator — never rebuild the whole page.
        if (state.status == LocationCaptureStatus.fetchingLocation ||
            state.status == LocationCaptureStatus.improvingAccuracy) {
          state = state.copyWith(
            status: LocationCaptureStatus.improvingAccuracy,
            accuracyMeters: reading.accuracy,
          );
        }
      },
    ).timeout(
      LocationAccuracyConfig.acquisitionTimeout + const Duration(seconds: 5),
      onTimeout: () => LocationAcquisition(best: null, readings: const [], timedOut: true),
    );

    // The attempt finished after [reset] (or after a newer one started): its
    // fix is stale, so it must not be written over the current state.
    if (generation != _generation) return;

    final best = acquisition.best;
    if (best == null) {
      state = state.copyWith(
        status: LocationCaptureStatus.error,
        errorMessage:
            'Could not get your location. Try moving to an open area or enter manually.',
      );
      return;
    }

    final poor = best.tier == AccuracyTier.poor;
    state = state.copyWith(
      deviceReading: best,
      accuracyMeters: best.accuracy,
      shopPin: LatLng(best.latitude, best.longitude),
      pinIsAdjusted: false,
      pinDriftMeters: 0,
      pinDriftConfirmed: false,
      // A real fix replaces the hand-placed-pin mode.
      mapOnly: false,
      status: poor
          ? LocationCaptureStatus.locationPoorAccuracy
          : LocationCaptureStatus.locationReady,
    );
  }

  /// Fallback that needs NO permission and NO GPS: the shopkeeper places the
  /// shop pin on the map by hand ("Choose Location on Map").
  ///
  /// Nothing is fabricated — [LocationCaptureState.mapOnly] is set so the UI
  /// and the submitted payload state that the coordinates were placed
  /// manually (backend `LocationSource.MANUAL`) and that no accuracy radius
  /// exists.
  void startMapOnlyCapture() {
    state = state.copyWith(
      status: LocationCaptureStatus.locationReady,
      mapOnly: true,
      clearError: true,
    );
  }

  /// Opens this app's page in the system settings — the only way back from a
  /// permanently denied location permission.
  Future<bool> openSystemSettings() => _location.openAppSettings();

  /// Opens the device location-services page — the way back from "GPS is off".
  Future<bool> openDeviceLocationSettings() =>
      _location.openLocationSettings();

  /// Moves the shop ENTRANCE pin; significant drift from the GPS fix is
  /// flagged and must be confirmed by the shopkeeper.
  void moveShopPin(LatLng pin) {
    final device = state.deviceReading;
    final drift = device == null
        ? 0.0
        : _location.distanceBetween(
            device.latitude, device.longitude, pin.latitude, pin.longitude);
    state = state.copyWith(
      shopPin: pin,
      pinIsAdjusted: true,
      pinDriftMeters: drift,
    );
  }

  /// "Are you sure this is your shop?" → Confirm.
  void confirmPinDrift() => state = state.copyWith(pinDriftConfirmed: true);

  /// Reverse geocode AFTER the final pin selection — never per GPS reading.
  Future<void> confirmLocation() async {
    final pin = state.shopPin;
    if (pin == null) return;
    state = state.copyWith(
      status: LocationCaptureStatus.reverseGeocoding,
      clearError: true,
    );
    PickedLocation address;
    try {
      final geo = await _geocoder.reverseGeocode(pin.latitude, pin.longitude);
      address = geo == null
          ? PickedLocation(latitude: pin.latitude, longitude: pin.longitude)
          : PickedLocation(
              latitude: pin.latitude,
              longitude: pin.longitude,
              addressLine: geo.formattedAddress,
              city: geo.city,
              state: geo.state,
              pincode: geo.pincode,
              country: 'India',
            );
    } catch (_) {
      // Reverse geocoding is supporting info only; GPS coordinates stay primary.
      address = PickedLocation(latitude: pin.latitude, longitude: pin.longitude);
    }
    state = state.copyWith(
      status: LocationCaptureStatus.readyForConfirmation,
      address: address,
    );
  }

  /// Editing the address text NEVER changes the coordinates.
  void editAddressText(String text) =>
      state = state.copyWith(addressLineOverride: text);

  /// Refresh a stale reading before final submission (no-op when fresh).
  Future<void> refreshIfStale() async {
    if (!state.isStale) return;
    await acquire();
    await confirmLocation();
  }

  /// Returns to the initial state. Bumps the generation first so an
  /// acquisition still running (the shopkeeper navigated away mid-fix) cannot
  /// write its late result into the cleared state — its GPS stream still closes
  /// itself via the `await for` in `acquireBestLocation`, but the reading is
  /// dropped instead of resurrecting a pin the shopkeeper never confirmed.
  void reset() {
    _generation++;
    state = const LocationCaptureState();
  }
}
