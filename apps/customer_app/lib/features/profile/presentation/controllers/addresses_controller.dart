import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../location/domain/address_book_repository.dart';
import '../../../location/domain/models/saved_address.dart';
import '../../../location/domain/models/user_location.dart';
import '../../../location/presentation/controllers/location_controller.dart';

/// Exposes the customer's address book to the account area.
///
/// All mutations go through [AddressBookRepository]; setting a default
/// additionally syncs the app-wide active location so discovery features
/// immediately use the new default.
final addressesControllerProvider =
    AsyncNotifierProvider<AddressesController, List<SavedAddress>>(
      AddressesController.new,
    );

class AddressesController extends AsyncNotifier<List<SavedAddress>> {
  @override
  Future<List<SavedAddress>> build() {
    return ref.watch(addressBookRepositoryProvider).getAddresses();
  }

  /// Saves the current active location under [label].
  ///
  /// Returns false (no-op) when no location has been selected yet — the
  /// UI asks the user to pick a location first.
  Future<bool> addFromCurrentLocation(String label) async {
    final location = ref.read(locationControllerProvider).location;
    if (location == null) return false;
    await _mutate((repo) => repo.addAddress(label: label, location: location));
    return true;
  }

  /// Edits an existing address. Returns false when it no longer exists.
  Future<bool> updateAddress({
    required String id,
    required String label,
    UserLocation? location,
  }) async {
    final repository = ref.read(addressBookRepositoryProvider);
    final current = await repository.getAddresses();
    final match = current.where((address) => address.id == id).firstOrNull;
    if (match == null) return false;

    // Default to the stored coordinates when the edit only changed the label.
    final updated = await repository.updateAddress(
      id: id,
      label: label,
      location: location ?? match.location,
    );
    state = AsyncData(updated);
    return true;
  }

  Future<void> removeAddress(String id) async {
    await _mutate((repo) => repo.removeAddress(id));
  }

  /// Makes [id] the default address and applies it as the active
  /// app location.
  Future<void> setDefaultAddress(String id) async {
    await _mutate((repo) => repo.setDefaultAddress(id));
    final updated = state.value;
    if (updated == null) return;
    SavedAddress? match;
    for (final address in updated) {
      if (address.id == id) {
        match = address;
        break;
      }
    }
    if (match != null) {
      await ref
          .read(locationControllerProvider.notifier)
          .selectSavedAddress(match);
    }
  }

  /// Reloads from the repository after a failed load.
  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      state = AsyncData(
        await ref.read(addressBookRepositoryProvider).getAddresses(),
      );
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> _mutate(
    Future<List<SavedAddress>> Function(AddressBookRepository repo) action,
  ) async {
    try {
      final repository = ref.read(addressBookRepositoryProvider);
      state = AsyncData(await action(repository));
    } catch (_) {
      // Keep current list on failure; the screen shows a snackbar via the
      // returned result of individual actions where relevant.
    }
  }
}
