import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/local_storage_driver.dart';

/// A simple local cache service that stores JSON-serializable data
/// with timestamps for stale-while-revalidate pattern.
///
/// This cache is used for non-sensitive, useful customer information
/// such as home feed data, product details, and shop details.
/// It does NOT cache inventory data to avoid presenting stale stock as live.
class LocalCacheService {
  final LocalStorageDriver _storage;
  static const Duration _defaultStaleDuration = Duration(minutes: 15);
  static const Duration _maxCacheDuration = Duration(hours: 2);

  LocalCacheService(this._storage);

  /// Namespace prefix for every key this cache owns.
  ///
  /// Doubles as the eviction filter for [clear]: a key belongs to the cache iff
  /// it starts with this. The `_v1_` lets a future payload format reuse the same
  /// logical keys without ever reading an older, incompatible entry.
  static const String _keyPrefix = 'cache_v1_';

/// Cache key prefix to avoid collisions
  String _cacheKey(String key) => '$_keyPrefix$key';

  /// Store data in cache with a timestamp.
  Future<void> put(String key, dynamic data) async {
    final cacheEntry = jsonEncode({
      'data': data,
      'cached_at': DateTime.now().toIso8601String(),
    });
    await _storage.setString(_cacheKey(key), cacheEntry);
  }

  /// Retrieve data from cache. Returns null if not found or expired.
  /// [staleDuration] controls how long before data is considered stale
  /// (but still returned). [maxAge] controls hard expiry.
  Future<CacheResult?> get(
    String key, {
    Duration staleDuration = _defaultStaleDuration,
    Duration maxAge = _maxCacheDuration,
  }) async {
    final raw = await _storage.getString(_cacheKey(key));
    if (raw == null) return null;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final data = decoded['data'];
      final cachedAt = DateTime.parse(decoded['cached_at'] as String);
      final age = DateTime.now().difference(cachedAt);

      if (age > maxAge) {
        // Hard expired - remove and return null
        await _storage.remove(_cacheKey(key));
        return null;
      }

      return CacheResult(
        data: data,
        isStale: age > staleDuration,
        cachedAt: cachedAt,
      );
    } catch (_) {
      // Corrupted cache entry
      await _storage.remove(_cacheKey(key));
      return null;
    }
  }

  /// Remove a cached entry.
  Future<void> remove(String key) async {
    await _storage.remove(_cacheKey(key));
  }

  /// Removes every cached entry, and ONLY cached entries.
  ///
  /// WHY THIS IS NOT `_storage.clear()`
  /// ---------------------------------
  /// This used to call `clear()` on the underlying [LocalStorageDriver], whose
  /// comment even conceded "We can't selectively clear". But that driver is
  /// SharedPreferences, and it holds EVERYTHING the app persists locally — the
  /// theme, the language, the analytics switches, the onboarding flag, saved
  /// products and shops, recent searches.
  ///
  /// So "clear the cache" silently wiped the customer's saved items, their
  /// theme, and sent them back through onboarding — from a method whose name
  /// promises nothing of the sort. Worse, the privacy screen tells a customer
  /// that clearing local data removes saved items while leaving the rest of
  /// their setup alone; a cache clear doing the opposite is exactly the kind of
  /// surprise that makes a privacy promise untrue.
  ///
  /// SharedPreferences can enumerate its own keys, so the fix is to remove only
  /// the ones this cache owns — anything carrying [_keyPrefix]. The entries are
  /// namespaced precisely so they can be told apart from everything else.
  Future<void> clear() async {
    final keys = await _storage.keys();
    for (final key in keys) {
      if (key.startsWith(_keyPrefix)) {
        await _storage.remove(key);
      }
    }
  }
}

class CacheResult {
  final dynamic data;
  final bool isStale;
  final DateTime cachedAt;

  CacheResult({
    required this.data,
    required this.isStale,
    required this.cachedAt,
  });
}

final localCacheServiceProvider = Provider<LocalCacheService>((ref) {
  final storage = ref.watch(localStorageDriverProvider);
  return LocalCacheService(storage);
});
