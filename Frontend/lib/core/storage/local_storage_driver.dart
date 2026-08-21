import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class LocalStorageDriver {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<List<String>?> getStringList(String key);
  Future<void> setStringList(String key, List<String> value);
  Future<void> remove(String key);
  Future<void> clear();
}

/// SharedPreferences-backed implementation for production use.
class SharedPreferencesStorageDriver implements LocalStorageDriver {
  final SharedPreferences _prefs;

  SharedPreferencesStorageDriver(this._prefs);

  @override
  Future<String?> getString(String key) async => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) async {
    await _prefs.setString(key, value);
  }

  @override
  Future<List<String>?> getStringList(String key) async =>
      _prefs.getStringList(key);

  @override
  Future<void> setStringList(String key, List<String> value) async {
    await _prefs.setStringList(key, value);
  }

  @override
  Future<void> remove(String key) async => _prefs.remove(key);

  @override
  Future<void> clear() async => _prefs.clear();
}

/// InMemory implementation used for unit testing and quick fallback.
class InMemoryStorageDriver implements LocalStorageDriver {
  final Map<String, dynamic> _data = {};

  @override
  Future<String?> getString(String key) async => _data[key] as String?;

  @override
  Future<void> setString(String key, String value) async => _data[key] = value;

  @override
  Future<List<String>?> getStringList(String key) async =>
      (_data[key] as List?)?.cast<String>();

  @override
  Future<void> setStringList(String key, List<String> value) async =>
      _data[key] = value;

  @override
  Future<void> remove(String key) async => _data.remove(key);

  @override
  Future<void> clear() async => _data.clear();
}

final localStorageDriverProvider = Provider<LocalStorageDriver>((ref) {
  // In production, this would be initialized with SharedPreferences.
  // For now, we use InMemoryStorageDriver as a safe default.
  // To switch to SharedPreferences, use:
  // final prefs = await SharedPreferences.getInstance();
  // return SharedPreferencesStorageDriver(prefs);
  return InMemoryStorageDriver();
});