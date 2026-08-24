import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_customer_app/core/storage/secure_storage_service.dart';
import 'package:hyperlocal_customer_app/features/location/domain/models/user_location.dart';
import 'package:hyperlocal_customer_app/features/location/presentation/controllers/location_controller.dart';
import 'package:hyperlocal_customer_app/features/profile/presentation/controllers/addresses_controller.dart';

/// In-memory stand-in for [SecureStorageService] shared by the address
/// book and the location controller (which it syncs with).
class _InMemorySecureStorage extends SecureStorageService {
  final Map<String, String> store = {};

  _InMemorySecureStorage() : super(const FlutterSecureStorage());

  @override
  Future<String?> read({required String key}) async => store[key];

  @override
  Future<void> write({required String key, required String value}) async {
    store[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    store.remove(key);
  }
}

void main() {
  group('AddressesController', () {
    late _InMemorySecureStorage storage;
    late ProviderContainer container;

    const patnaLocation = UserLocation(
      latitude: 25.5941,
      longitude: 85.1376,
      address: 'Patna Center',
      city: 'Patna',
      isSelected: true,
    );

    setUp(() {
      storage = _InMemorySecureStorage();
      container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    Future<List<dynamic>> waitForLoad() async {
      container.read(addressesControllerProvider);
      await container.pump();
      return container.read(addressesControllerProvider).value ?? [];
    }

    /// Puts the app-wide active location in place, like onboarding does.
    Future<void> seedActiveLocation(UserLocation location) async {
      await storage.write(
        key: 'user_saved_location',
        value: jsonEncode(location.toJson()),
      );
      await container.read(locationControllerProvider.notifier).loadSavedLocation();
    }

    test('loads persisted addresses', () async {
      final addresses = await waitForLoad();
      expect(addresses, isEmpty);
    });

    test('addFromCurrentLocation returns false without a location', () async {
      await waitForLoad();

      final ok = await container
          .read(addressesControllerProvider.notifier)
          .addFromCurrentLocation('Home');

      expect(ok, isFalse);
      expect(container.read(addressesControllerProvider).value ?? [], isEmpty);
    });

    test('addFromCurrentLocation saves the active location under a label',
        () async {
      await waitForLoad();
      await seedActiveLocation(patnaLocation);

      final ok = await container
          .read(addressesControllerProvider.notifier)
          .addFromCurrentLocation('Home');
      await container.pump();

      expect(ok, isTrue);
      final addresses = container.read(addressesControllerProvider).value ?? [];
      expect(addresses.length, 1);
      expect(addresses.first.label, 'Home');
      expect(addresses.first.location.latitude, patnaLocation.latitude);
    });

    test('removeAddress deletes the entry and updates state', () async {
      await waitForLoad();
      await seedActiveLocation(patnaLocation);
      final controller = container.read(addressesControllerProvider.notifier);
      await controller.addFromCurrentLocation('Home');
      await container.pump();

      final id =
          (container.read(addressesControllerProvider).value ?? []).first.id;
      await controller.removeAddress(id);
      await container.pump();

      expect(container.read(addressesControllerProvider).value ?? [], isEmpty);
    });

    test('setDefaultAddress marks the default and syncs the active location',
        () async {
      await waitForLoad();
      // Start with Patna as active.
      await seedActiveLocation(patnaLocation);
      final controller = container.read(addressesControllerProvider.notifier);
      await controller.addFromCurrentLocation('Home');

      // Add a second address from a different location.
      const gayaLocation = UserLocation(
        latitude: 24.7914,
        longitude: 85.0002,
        address: 'Gaya Center',
        city: 'Gaya',
        isSelected: true,
      );
      await seedActiveLocation(gayaLocation);
      await controller.addFromCurrentLocation('Work');
      await container.pump();

      final addresses = container.read(addressesControllerProvider).value ?? [];
      expect(addresses.length, 2);

      // Make the first ("Home") the default.
      await controller.setDefaultAddress(addresses.first.id);
      await container.pump();

      final updated = container.read(addressesControllerProvider).value ?? [];
      final selected = updated.where((a) => a.isSelected).toList();
      expect(selected.length, 1);
      expect(selected.first.label, 'Home');

      // Active app location now points at the default address.
      final activeLocation = container.read(locationControllerProvider).location;
      expect(activeLocation, isNotNull);
      expect(activeLocation!.latitude, patnaLocation.latitude);
    });
  });
}
