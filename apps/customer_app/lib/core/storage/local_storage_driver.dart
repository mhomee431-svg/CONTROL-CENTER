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
///
/// Resolves the [SharedPreferences] singleton lazily on first access so the
/// driver can be constructed synchronously from a Riverpod provider without
/// blocking app startup. `getInstance()` caches after the first call, so
/// per-call awaits are effectively free.
class SharedPreferencesStorageDriver implements LocalStorageDriver {
  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  @override
  Future<String?> getString(String key) async =>
      (await _prefs()).getString(key);

  @override
  Future<void> setString(String key, String value) async {
    await (await _prefs()).setString(key, value);
  }

  @override
  Future<List<String>?> getStringList(String key) async =>
      (await _prefs()).getStringList(key);

  @override
  Future<void> setStringList(String key, List<String> value) async {
    await (await _prefs()).setStringList(key, value);
  }

  @override
  Future<void> remove(String key) async => (await _prefs()).remove(key);

  @override
  Future<void> clear() async => (await _prefs()).clear();
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
  // Production default: persisted device storage so favorites, history and
  // settings survive restarts (offline foundation). Tests override this
  // provider with [InMemoryStorageDriver].
  return SharedPreferencesStorageDriver();
});
