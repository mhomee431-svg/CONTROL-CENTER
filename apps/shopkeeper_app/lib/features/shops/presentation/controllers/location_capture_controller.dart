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
  Future<void> acquire() async {
    state = state.copyWith(
      status: LocationCaptureStatus.fetchingLocation,
      clearError: true,
    );
    final acquisition = await _location.acquireBestLocation(
      onReading: (reading) {
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

  void reset() => state = const LocationCaptureState();
}
