import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistent record of the product searches the shopkeeper actually ran.
///
/// Scope (deliberate):
///   * product searches ONLY — the products list, the inventory scopes and
///     the price list all search the same catalog rows through the same
///     predicate ([ProductSearch]), so one shared history serves all three
///     instead of three histories disagreeing about "recent";
///   * SUBMITTED terms only — keystrokes never touch this store. A term is
///     recorded when the shopkeeper submits it (keyboard search action) or
///     when the submitted text is applied (focus-loss flush in
///     [DebouncedSearchField]); a cancelled draft is not history;
///   * per SHOP — the key is namespaced by the shop id, the same rule as
///     `ProductsSnapshotStore`, so one shop's terms never leak into another;
///   * best-effort I/O — a store failure must never break the list: every
///     method swallows platform errors and degrades to the in-memory state.
///
/// Privacy: terms are product names the shopkeeper typed (not PII), kept in
/// the SAME encrypted store as the token/snapshot data, capped at
/// [maxTerms] entries, and wiped on logout via [clearAll] (the auth
/// controller already calls this alongside the snapshot wipe).
abstract class RecentSearchesStore {
  /// Most-recent-first terms for [shopKey], or empty when none.
  Future<List<String>> read(String shopKey);

  Future<void> save(String shopKey, List<String> terms);

  /// Removes every shop's terms (logout / explicit data reset).
  Future<void> clearAll();
}

/// Production store backed by flutter_secure_storage (encrypted on device) —
/// the same pattern as `SecureProductsSnapshotStore` and the token store.
class SecureRecentSearchesStore implements RecentSearchesStore {
  const SecureRecentSearchesStore([
    this._storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage _storage;

  static const String _prefix = 'sk_recent_searches_';

  String _key(String shopKey) => '$_prefix$shopKey';

  @override
  Future<List<String>> read(String shopKey) async {
    try {
      final raw = await _storage.read(key: _key(shopKey));
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<String>().toList(growable: false);
    } catch (_) {
      // A corrupt entry is simply "no history" — the list still searches.
      return const [];
    }
  }

  @override
  Future<void> save(String shopKey, List<String> terms) async {
    try {
      await _storage.write(key: _key(shopKey), value: jsonEncode(terms));
    } catch (_) {
      // History that cannot be stored must never break the live path.
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
      // Nothing to do — the next record overwrites anyway.
    }
  }
}

/// In-memory store for unit/widget tests (no platform channels).
class InMemoryRecentSearchesStore implements RecentSearchesStore {
  final Map<String, List<String>> _values = {};

  /// How many times [clearAll] ran — asserted for the logout wipe.
  int clearAllCount = 0;

  @override
  Future<List<String>> read(String shopKey) async =>
      List<String>.unmodifiable(_values[shopKey] ?? const []);

  @override
  Future<void> save(String shopKey, List<String> terms) async =>
      _values[shopKey] = List<String>.unmodifiable(terms);

  @override
  Future<void> clearAll() async {
    clearAllCount++;
    _values.clear();
  }
}

final recentSearchesStoreProvider = Provider<RecentSearchesStore>(
  (ref) => const SecureRecentSearchesStore(),
);
