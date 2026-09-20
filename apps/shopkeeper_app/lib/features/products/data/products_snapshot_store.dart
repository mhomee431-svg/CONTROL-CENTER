import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Read-only offline cache of the products/inventory list.
///
/// Scope (deliberate): this store keeps the LAST SUCCESSFUL
/// `GET /inventory?view=list` payload per shop so that, while offline, the
/// products screen can still render the last synced list. The rules that keep
/// it safe:
///
///   * it is written only after a REAL backend response — never a guess;
///   * it is read only when a live fetch fails with the *offline* state, never
///     as a shortcut for fresh data while online;
///   * the payload comes back flagged as cached (`fromCache`) and the lists
///     that render it say so via `CachedDataNotice` — a stale quantity or
///     price that LOOKS live is worse than no data;
///   * payloads above ~512 KB are skipped (a secure-storage value that big
///     would slow every write for a marginal offline benefit);
///   * it is wiped on logout so one account's catalogue never leaks into the
///     next session.
///
/// There is deliberately NO write queue and no optimistic writes: mutations
/// always require the backend, so a change can never be reported as saved when
/// the server has not accepted it.
abstract class ProductsSnapshotStore {
  /// `null` when this shop has no snapshot (or it was corrupt/unreadable).
  Future<Map<String, dynamic>?> read(String shopKey);

  Future<void> save(String shopKey, Map<String, dynamic> data);

  /// Removes every snapshot (logout / explicit data reset).
  Future<void> clearAll();
}

/// Production store backed by flutter_secure_storage (encrypted on device) —
/// the same pattern as `SecureNotificationPreferencesStore`.
class SecureProductsSnapshotStore implements ProductsSnapshotStore {
  const SecureProductsSnapshotStore([
    this._storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage _storage;

  static const String _prefix = 'sk_products_snapshot_';
  static const int _maxJsonLength = 512 * 1024;

  String _key(String shopKey) => '$_prefix$shopKey';

  @override
  Future<Map<String, dynamic>?> read(String shopKey) async {
    try {
      final raw = await _storage.read(key: _key(shopKey));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      // A corrupt snapshot is simply "no snapshot" — the offline error state
      // is the honest outcome then, never a half-parsed list.
      return null;
    }
  }

  @override
  Future<void> save(String shopKey, Map<String, dynamic> data) async {
    try {
      final encoded = jsonEncode(data);
      if (encoded.length > _maxJsonLength) return;
      await _storage.write(key: _key(shopKey), value: encoded);
    } catch (_) {
      // A snapshot that cannot be stored must never break the live path.
    }
  }

  @override
  Future<void> clearAll() async {
    try {
      final all = await _storage.readAll();
      for (final key in all.keys) {
        if (key.startsWith(_prefix)) await _storage.delete(key: key);
      }
    } catch (_) {
      // Nothing to do — the next successful fetch overwrites anyway.
    }
  }
}

/// In-memory store for unit/widget tests (no platform channels).
class InMemoryProductsSnapshotStore implements ProductsSnapshotStore {
  final Map<String, Map<String, dynamic>> _values = {};

  /// How many times [clearAll] ran — asserted for the logout wipe.
  int clearAllCount = 0;

  @override
  Future<Map<String, dynamic>?> read(String shopKey) async => _values[shopKey];

  @override
  Future<void> save(String shopKey, Map<String, dynamic> data) async =>
      _values[shopKey] = data;

  @override
  Future<void> clearAll() async {
    clearAllCount++;
    _values.clear();
  }
}

final productsSnapshotStoreProvider = Provider<ProductsSnapshotStore>(
  (ref) => SecureProductsSnapshotStore(),
);
