import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class SecureStorageDriver {
  Future<void> write({required String key, required String value});
  Future<String?> read({required String key});
  Future<void> delete({required String key});
  Future<void> deleteAll();
}

class InMemorySecureStorageDriver implements SecureStorageDriver {
  final Map<String, String> _vault = {};

  @override
  Future<void> write({required String key, required String value}) async {
    _vault[key] = value;
  }

  @override
  Future<String?> read({required String key}) async => _vault[key];

  @override
  Future<void> delete({required String key}) async => _vault.remove(key);

  @override
  Future<void> deleteAll() async => _vault.clear();
}

final secureStorageDriverProvider = Provider<SecureStorageDriver>((ref) {
  return InMemorySecureStorageDriver();
});