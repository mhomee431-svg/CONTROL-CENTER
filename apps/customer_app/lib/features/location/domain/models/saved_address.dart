import 'package:freezed_annotation/freezed_annotation.dart';

import 'user_location.dart';

part 'saved_address.freezed.dart';
part 'saved_address.g.dart';

/// A customer-saved address (e.g. Home, Work, relative's house).
///
/// This is the foundation for the "Saved Addresses" feature. It wraps
/// a [UserLocation] with a stable ID and a user-friendly label so the
/// customer can quickly re-select a frequently used location.
@freezed
abstract class SavedAddress with _$SavedAddress {
  const factory SavedAddress({
    /// Stable unique ID (UUID) for this saved address.
    required String id,

    /// User-friendly label (e.g. "Home", "Work", "Grandma's House").
    required String label,

    /// The underlying location data.
    required UserLocation location,

    /// Whether this is the currently selected/active address.
    @Default(false) bool isSelected,

    /// Epoch milliseconds when this address was saved.
    @JsonKey(name: 'savedAtMs') @Default(0) int savedAtMs,
  }) = _SavedAddress;

  const SavedAddress._();

  factory SavedAddress.fromJson(Map<String, dynamic> json) =>
      _$SavedAddressFromJson(json);

  /// Convenience constructor with a `DateTime` for `savedAt`.
  factory SavedAddress.create({
    required String id,
    required String label,
    required UserLocation location,
    bool isSelected = false,
    DateTime? savedAt,
  }) => SavedAddress(
    id: id,
    label: label,
    location: location,
    isSelected: isSelected,
    savedAtMs: savedAt?.millisecondsSinceEpoch ?? 0,
  );

  /// Time the address was saved (null if never set).
  DateTime? get savedAt =>
      savedAtMs == 0 ? null : DateTime.fromMillisecondsSinceEpoch(savedAtMs);

  /// Creates a copy marked as the selected address.
  SavedAddress select() =>
      copyWith(isSelected: true, location: location.select());
}
