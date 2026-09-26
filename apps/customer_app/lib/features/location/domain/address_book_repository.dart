import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/secure_storage_service.dart';
import 'models/saved_address.dart';
import 'models/user_location.dart';

/// Contract for managing the customer's saved addresses
/// (the address book shown in the account area).
///
/// Implementations live local-first: addresses are device data until a
/// backend customer-address API ships; swapping in an API-backed
/// implementation will require no UI changes.
abstract class AddressBookRepository {
  /// All saved addresses, insertion order preserved.
  Future<List<SavedAddress>> getAddresses();

  /// Persists a new address entry.
  Future<List<SavedAddress>> addAddress({
    required String label,
    required UserLocation location,
  });

  /// Updates an existing address's label and/or coordinates.
  ///
  /// Returns the updated list. A missing [id] is a no-op rather than an error
  /// so a stale screen can never crash the address book.
  Future<List<SavedAddress>> updateAddress({
    required String id,
    required String label,
    required UserLocation location,
  });

  /// Removes an address by id.
  Future<List<SavedAddress>> removeAddress(String id);

  /// Marks [id] as the default address (exactly one selected at a time).
  Future<List<SavedAddress>> setDefaultAddress(String id);
}

/// Secure-storage backed implementation.
///
/// Uses the same storage key and JSON shape as the location onboarding
/// flow (`user_saved_addresses`), so addresses saved from either surface
/// stay consistent.
class LocalAddressBookRepository implements AddressBookRepository {
  static const storageKey = 'user_saved_addresses';

  /// Monotonic per-process counter. Guarantees unique IDs even when two
  /// consecutive [addAddress] calls land on the same clock tick (observed
  /// on Windows, where `DateTime.now()` granularity can repeat).
  static int _idSequence = 0;

  final SecureStorageService _storage;

  LocalAddressBookRepository(this._storage);

  /// Collision-resistant ID: timestamp + process sequence + random suffix.
  String _generateId() {
    _idSequence += 1;
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final sequence = _idSequence.toRadixString(36);
    final randomSuffix = Random().nextInt(1 << 31).toRadixString(36);
    return '$timestamp-$sequence-$randomSuffix';
  }

  @override
  Future<List<SavedAddress>> getAddresses() async {
    final json = await _storage.read(key: storageKey);
    if (json == null) return [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(SavedAddress.fromJson)
          .toList();
    } catch (_) {
      // Corrupt payload — treat as empty rather than crashing the UI.
      return [];
    }
  }

  @override
  Future<List<SavedAddress>> addAddress({
    required String label,
    required UserLocation location,
  }) async {
    final addresses = await getAddresses();
    final address = SavedAddress.create(
      id: _generateId(),
      label: label,
      location: location,
      savedAt: DateTime.now(),
    );
    addresses.add(address);
    await _persist(addresses);
    return addresses;
  }

  @override
  Future<List<SavedAddress>> updateAddress({
    required String id,
    required String label,
    required UserLocation location,
  }) async {
    final addresses = await getAddresses();
    final index = addresses.indexWhere((a) => a.id == id);
    if (index == -1) return addresses;

    final existing = addresses[index];
    // Keep the selected flag and original save time stable across an edit.
    addresses[index] = existing.copyWith(
      label: label,
      location: existing.isSelected ? location.select() : location,
    );
    await _persist(addresses);
    return addresses;
  }

  @override
  Future<List<SavedAddress>> removeAddress(String id) async {
    final addresses = await getAddresses();
    addresses.removeWhere((a) => a.id == id);
    await _persist(addresses);
    return addresses;
  }

  @override
  Future<List<SavedAddress>> setDefaultAddress(String id) async {
    final addresses = await getAddresses();
    final updated = [
      for (final address in addresses)
        address.id == id
            ? address.select()
            : address.copyWith(isSelected: false),
    ];
    await _persist(updated);
    return updated;
  }

  Future<void> _persist(List<SavedAddress> addresses) async {
    await _storage.write(
      key: storageKey,
      value: jsonEncode(addresses.map((a) => a.toJson()).toList()),
    );
  }
}

final addressBookRepositoryProvider = Provider<AddressBookRepository>((ref) {
  return LocalAddressBookRepository(ref.watch(secureStorageProvider));
});
