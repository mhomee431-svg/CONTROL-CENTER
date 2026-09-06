import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../data/location_accuracy_config.dart';
import '../data/location_service.dart';

/// Explicit location-capture states (INITIAL → … → READY_FOR_CONFIRMATION).
enum LocationCaptureStatus {
  initial,
  requestingPermission,
  fetchingLocation,
  improvingAccuracy,
  locationReady,
  locationPoorAccuracy,
  locationPermissionDenied,
  locationServiceDisabled,
  reverseGeocoding,
  readyForConfirmation,
  saving,
  success,
  error,
}

/// Immutable state for the shop-location capture flow.
///
/// DEVICE LOCATION and SHOP LOCATION are kept conceptually distinct:
///   - [deviceReading] — where the phone's GPS fix was taken.
///   - [shopPin] — the shop entrance pin the shopkeeper confirms.
/// Editing the address text NEVER mutates [shopPin] coordinates.
class LocationCaptureState {
  const LocationCaptureState({
    this.status = LocationCaptureStatus.initial,
    this.permission,
    this.deviceReading,
    this.shopPin,
    this.accuracyMeters,
    this.pinIsAdjusted = false,
    this.pinDriftMeters,
    this.pinDriftConfirmed = false,
    this.address,
    this.addressLineOverride,
    this.isSaving = false,
    this.errorMessage,
  });

  final LocationCaptureStatus status;
  final LocationPermissionStatus? permission;

  /// Best GPS reading captured from the device (may be null until acquired).
  final GpsReading? deviceReading;

  /// The shop entrance pin (initialised to the device fix, then adjustable).
  final LatLng? shopPin;

  /// Accuracy radius (meters) of the reading backing the current pin.
  final double? accuracyMeters;

  /// True once the shopkeeper manually moved the pin.
  final bool pinIsAdjusted;

  /// Distance between the shop pin and the device GPS fix.
  final double? pinDriftMeters;

  /// True after the shopkeeper confirmed a significant pin drift.
  final bool pinDriftConfirmed;

  /// Reverse-geocoded address for the current pin (supporting info only).
  final PickedLocation? address;

  /// Shopkeeper-edited address text (kept separate from coordinates).
  final String? addressLineOverride;

  final bool isSaving;
  final String? errorMessage;

  AccuracyTier get tier => LocationAccuracyConfig.tierFor(accuracyMeters);

  bool get isStale => deviceReading != null && deviceReading!.isStale();

  bool get hasUsableAccuracy =>
      accuracyMeters != null &&
      accuracyMeters! <= LocationAccuracyConfig.minimumUsableAccuracyMeters;

  bool get canConfirm =>
      shopPin != null &&
      deviceReading != null &&
      hasUsableAccuracy &&
      (pinDriftMeters == null ||
          pinDriftMeters! <= LocationAccuracyConfig.pinDriftWarningMeters ||
          pinDriftConfirmed);

  /// Final address text: shopkeeper override wins over the detected one.
  String? get effectiveAddressText =>
      (addressLineOverride?.trim().isNotEmpty ?? false)
          ? addressLineOverride
          : address?.displayLines.join('\n');

  LocationCaptureState copyWith({
    LocationCaptureStatus? status,
    LocationPermissionStatus? permission,
    GpsReading? deviceReading,
    LatLng? shopPin,
    double? accuracyMeters,
    bool? pinIsAdjusted,
    double? pinDriftMeters,
    bool? pinDriftConfirmed,
    PickedLocation? address,
    String? addressLineOverride,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
  }) {
    return LocationCaptureState(
      status: status ?? this.status,
      permission: permission ?? this.permission,
      deviceReading: deviceReading ?? this.deviceReading,
      shopPin: shopPin ?? this.shopPin,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      pinIsAdjusted: pinIsAdjusted ?? this.pinIsAdjusted,
      pinDriftMeters: pinDriftMeters ?? this.pinDriftMeters,
      pinDriftConfirmed: pinDriftConfirmed ?? this.pinDriftConfirmed,
      address: address ?? this.address,
      addressLineOverride: addressLineOverride ?? this.addressLineOverride,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Final, shopkeeper-confirmed location handed back to the registration flow.
///
/// Coordinates and human-readable address are separate fields by design:
/// editing the address text must never move the pin.
class CapturedShopLocation {
  const CapturedShopLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.capturedAt,
    this.addressText,
    this.city,
    this.state,
    this.pincode,
    this.locationType = 'SHOP_ENTRANCE',
    this.integrityStatus = 'UNKNOWN',
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime capturedAt;
  final String? addressText;
  final String? city;
  final String? state;
  final String? pincode;

  /// Always a customer access point — SHOP_ENTRANCE preferred.
  final String locationType;

  /// Client-side mock/suspicious signal (NORMAL | SUSPICIOUS | UNKNOWN).
  final String integrityStatus;

  Map<String, dynamic> toLocationMeta() => {
        'location_source': 'GPS',
        'location_type': locationType,
        'location_status': 'CAPTURED',
        'location_integrity_status': integrityStatus,
        'accuracy_meters': accuracyMeters,
        'location_captured_at': capturedAt.toUtc().toIso8601String(),
        'location_verified': true,
      };
}
