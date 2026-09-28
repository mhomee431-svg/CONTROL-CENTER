import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/security/secure_storage_driver.dart';

void main() {
  group('InMemorySecureStorageDriver', () {
    test('writes and reads data correctly', () async {
      final driver = InMemorySecureStorageDriver();

      await driver.write(key: 'auth_token', value: 'jwt-token-abc123');
      final value = await driver.read(key: 'auth_token');

      expect(value, equals('jwt-token-abc123'));
    });

    test('returns null for missing keys', () async {
      final driver = InMemorySecureStorageDriver();

      final value = await driver.read(key: 'non_existent');

      expect(value, isNull);
    });

    test('deletes data correctly', () async {
      final driver = InMemorySecureStorageDriver();
      await driver.write(key: 'auth_token', value: 'jwt-token-abc123');

      await driver.delete(key: 'auth_token');
      final value = await driver.read(key: 'auth_token');

      expect(value, isNull);
    });

    test('deleteAll clears all data', () async {
      final driver = InMemorySecureStorageDriver();
      await driver.write(key: 'auth_token', value: 'jwt-token-abc123');
      await driver.write(key: 'user_id', value: 'user-42');

      await driver.deleteAll();

      expect(await driver.read(key: 'auth_token'), isNull);
      expect(await driver.read(key: 'user_id'), isNull);
    });
  });
}
