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

  /// Cache key prefix to avoid collisions
  String _cacheKey(String key) => 'cache_v1_$key';

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

  /// Clear all cached entries.
  Future<void> clear() async {
    // We can't selectively clear, but we can clear all storage
    // In practice, this is fine for a local cache
    await _storage.clear();
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
