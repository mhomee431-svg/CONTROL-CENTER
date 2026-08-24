import 'package:freezed_annotation/freezed_annotation.dart';
import 'postgis_point.dart';

part 'user_location.freezed.dart';
part 'user_location.g.dart';

/// Represents a user-selected or device-derived location.
///
/// Fields marked "nullable" are optional because they may be unknown
/// when we only have raw coordinates (e.g. reverse geocoding failed).
@freezed
abstract class UserLocation with _$UserLocation {
  const factory UserLocation({
    required double latitude,
    required double longitude,

    /// Human-readable address (e.g. "123 MG Road, Aayakar Bhawan").
    @Default('') String address,

    /// City / locality name.
    @Default('') String city,

    /// State / province name.
    @Default('') String state,

    /// Postal code (PIN code).
    @Default('') String pincode,

    /// Convenience label (e.g. "Home", "Work", "Patna Center").
    /// Falls back to `city` when empty.
    @Default('') String label,

    /// True when the user manually picked this location
    /// (instead of it coming from the device GPS).
    @Default(false) bool isManual,

    /// True when coordinates are approximate (e.g. city-centre fallback
    /// when reverse geocoding failed or GPS accuracy is low).
    @Default(false) bool isApproximate,

    /// GPS accuracy in meters (0 = unknown).
    @Default(0.0) double accuracyMeters,

    /// Whether this is the currently selected/active location.
    @Default(false) bool isSelected,

    /// Epoch milliseconds when this location was captured.
    @JsonKey(name: 'capturedAtMs')
    @Default(0)
    int capturedAtMs,
  }) = _UserLocation;

  const UserLocation._();

  factory UserLocation.fromJson(Map<String, dynamic> json) => _$UserLocationFromJson(json);

  /// Convenience constructor with an ISO-8601 `DateTime` for `capturedAt`.
  factory UserLocation.withCapturedAt({
    required double latitude,
    required double longitude,
    String address = '',
    String city = '',
    String state = '',
    String pincode = '',
    String label = '',
    bool isManual = false,
    bool isApproximate = false,
    double accuracyMeters = 0,
    bool isSelected = false,
    DateTime? capturedAt,
  }) =>
      UserLocation(
        latitude: latitude,
        longitude: longitude,
        address: address,
        city: city,
        state: state,
        pincode: pincode,
        label: label,
        isManual: isManual,
        isApproximate: isApproximate,
        accuracyMeters: accuracyMeters,
        isSelected: isSelected,
        capturedAtMs: capturedAt?.millisecondsSinceEpoch ?? 0,
      );

  /// PostGIS-compatible representation for backend integration.
  PostGisPoint get postgis => PostGisPoint(latitude: latitude, longitude: longitude);

  /// Validates coordinates are within real-world bounds.
  bool get hasValidCoordinates =>
      latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180;

  /// Whether this location is usable for nearby-shop discovery.
  bool get isValidLocation => hasValidCoordinates && !isApproximate;

  /// Display label that falls back to city or "Unknown".
  String get displayLabel => label.isNotEmpty ? label : (city.isNotEmpty ? city : 'Unknown');

  /// Reverse geocoding summary: `address, city, state pincode`.
  String get displayAddress {
    final parts = [
      if (address.isNotEmpty) address,
      if (city.isNotEmpty) city,
      if (state.isNotEmpty) state,
      if (pincode.isNotEmpty) pincode,
    ];
    return parts.join(', ');
  }

  /// Time the location was captured (null if never set).
  DateTime? get capturedAt => capturedAtMs == 0 ? null : DateTime.fromMillisecondsSinceEpoch(capturedAtMs);

  /// Creates a copy marked as the selected/current location.
  UserLocation select() => copyWith(isSelected: true);
}