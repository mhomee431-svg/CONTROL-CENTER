import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/storage/secure_storage_service.dart';
import 'package:hyperlocal_app/features/location/domain/address_book_repository.dart';
import 'package:hyperlocal_app/features/location/domain/models/user_location.dart';

/// In-memory stand-in for [SecureStorageService] so the local repository
/// can be tested without platform channels.
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
  group('LocalAddressBookRepository', () {
    late _InMemorySecureStorage storage;
    late LocalAddressBookRepository repository;

    const location = UserLocation(
      latitude: 25.5941,
      longitude: 85.1376,
      address: 'Patna Center',
      city: 'Patna',
    );

    setUp(() {
      storage = _InMemorySecureStorage();
      repository = LocalAddressBookRepository(storage);
    });

    test('starts empty', () async {
      expect(await repository.getAddresses(), isEmpty);
    });

    test('addAddress persists under the shared storage key', () async {
      await repository.addAddress(label: 'Home', location: location);

      final addresses = await repository.getAddresses();
      expect(addresses.length, 1);
      expect(addresses.first.label, 'Home');
      expect(addresses.first.location, location);
      expect(addresses.first.isSelected, isFalse);
      // Key compatibility with the location onboarding flow.
      expect(storage.store.containsKey('user_saved_addresses'), isTrue);
    });

    test('removeAddress deletes only the matching entry', () async {
      final first = await repository.addAddress(label: 'Home', location: location);
      final both = await repository.addAddress(
        label: 'Work',
        location: const UserLocation(
          latitude: 24.7,
          longitude: 85.0,
          address: 'Gaya Center',
          city: 'Gaya',
        ),
      );

      final remaining = await repository.removeAddress(first.last.id);

      expect(remaining.length, 1);
      expect(remaining.first.label, 'Work');
      expect(both.length, 2);
    });

    test('rapid consecutive adds produce unique ids (no clock-tick collision)',
        () async {
      // Regression: ids were pure DateTime.now() microseconds and could
      // repeat on coarse timers, making removeAddress delete both entries.
      for (var i = 0; i < 25; i++) {
        await repository.addAddress(label: 'Addr $i', location: location);
      }

      final addresses = await repository.getAddresses();
      final ids = addresses.map((a) => a.id).toList();
      expect(ids.length, 25);
      expect(ids.toSet().length, 25, reason: 'every address id must be unique');
    });

    test('setDefaultAddress makes exactly one address the default', () async {
      final home = await repository.addAddress(label: 'Home', location: location);
      final work = await repository.addAddress(
        label: 'Work',
        location: const UserLocation(
          latitude: 24.7,
          longitude: 85.0,
          address: 'Gaya Center',
          city: 'Gaya',
        ),
      );
      final workId = work.last.id;

      final updated = await repository.setDefaultAddress(workId);

      expect(updated.where((a) => a.isSelected).map((a) => a.id), [workId]);
      expect(updated.firstWhere((a) => a.id == workId).isSelected, isTrue);
      expect(updated.firstWhere((a) => a.label == 'Home').isSelected, isFalse);

      // Switching defaults clears the previous one.
      final switched = await repository.setDefaultAddress(home.first.id);
      expect(switched.where((a) => a.isSelected).map((a) => a.id),
          [home.first.id]);
    });

    test('corrupt stored payload degrades to an empty list', () async {
      await storage.write(key: 'user_saved_addresses', value: '{broken');

      expect(await repository.getAddresses(), isEmpty);
    });
  });
}
