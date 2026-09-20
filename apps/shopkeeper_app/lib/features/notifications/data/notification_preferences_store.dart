import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/notification_models.dart';

/// Persistence for [NotificationPreferences].
///
/// WHY DEVICE-LOCAL: the shopkeeper backend has no notification-settings
/// endpoint yet (only the customer-scoped `/api/v1/notifications/preferences`,
/// whose payload is customer-shaped). Instead of inventing an endpoint, the
/// shopkeeper app keeps the preferences on the device, keyed by the signed-in
/// user, so they survive app restarts.
///
/// The abstraction mirrors `TokenStore` on purpose: tests inject
/// [InMemoryNotificationPreferencesStore] (no platform channels) and the future
/// server sync gets exactly ONE seam to hook into — swap
/// [notificationPreferencesStoreProvider] for an API-backed implementation and
/// no screen changes.
abstract class NotificationPreferencesStore {
  /// `null` when this user has never saved preferences (→ model defaults).
  Future<NotificationPreferences?> read(String userKey);

  Future<void> write(String userKey, NotificationPreferences preferences);

  /// Removes this user's saved preferences, so the next read falls back to the
  /// model defaults. Used by *Data & storage* so a shopkeeper can reset
  /// delivery preferences without signing out.
  Future<void> clear(String userKey);
}

/// Production store backed by flutter_secure_storage (encrypted on device).
class SecureNotificationPreferencesStore
    implements NotificationPreferencesStore {
  const SecureNotificationPreferencesStore([
    this._storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage _storage;

  static const String _prefix = 'sk_notification_preferences_';

  String _key(String userKey) => '$_prefix$userKey';

  @override
  Future<NotificationPreferences?> read(String userKey) async {
    final raw = await _storage.read(key: _key(userKey));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return NotificationPreferences.fromJson(decoded);
    } catch (_) {
      // Corrupt / legacy value: fall back to defaults rather than throwing on
      // a settings screen.
      return null;
    }
  }

  @override
  Future<void> write(String userKey, NotificationPreferences preferences) =>
      _storage.write(
        key: _key(userKey),
        value: jsonEncode(preferences.toJson()),
      );

  @override
  Future<void> clear(String userKey) => _storage.delete(key: _key(userKey));
}

/// In-memory store for widget/unit tests.
class InMemoryNotificationPreferencesStore
    implements NotificationPreferencesStore {
  final Map<String, NotificationPreferences> _values = {};

  @override
  Future<NotificationPreferences?> read(String userKey) async =>
      _values[userKey];

  @override
  Future<void> write(
    String userKey,
    NotificationPreferences preferences,
  ) async {
    _values[userKey] = preferences;
  }

  @override
  Future<void> clear(String userKey) async {
    _values.remove(userKey);
  }
}

/// Default binding — override in tests with ProviderScope overrides.
final notificationPreferencesStoreProvider =
    Provider<NotificationPreferencesStore>(
  (ref) => const SecureNotificationPreferencesStore(),
);