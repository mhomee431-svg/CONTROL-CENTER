import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final secureStorageProvider = Provider((ref) => SecureStorageService(const FlutterSecureStorage()));

class SecureStorageService {
  final FlutterSecureStorage _storage;

  SecureStorageService(this._storage);

  static const String _tokenKey = 'auth_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _sessionIdKey = 'session_id';
  static const String _guestKey = 'is_guest';
  static const String _deviceIdKey = 'device_id';

  // ── Access token ─────────────────────────────────────────────────────
  Future<void> saveToken(String token) async => await _storage.write(key: _tokenKey, value: token);

  Future<String?> getToken() async => await _storage.read(key: _tokenKey);

  Future<void> deleteToken() async => await _storage.delete(key: _tokenKey);

  // ── Refresh token ────────────────────────────────────────────────────
  Future<void> saveRefreshToken(String refreshToken) async =>
      await _storage.write(key: _refreshTokenKey, value: refreshToken);

  Future<String?> getRefreshToken() async => await _storage.read(key: _refreshTokenKey);

  Future<void> deleteRefreshToken() async => await _storage.delete(key: _refreshTokenKey);

  // ── Session ID ───────────────────────────────────────────────────────
  Future<void> saveSessionId(String sessionId) async =>
      await _storage.write(key: _sessionIdKey, value: sessionId);

  Future<String?> getSessionId() async => await _storage.read(key: _sessionIdKey);

  Future<void> deleteSessionId() async => await _storage.delete(key: _sessionIdKey);

  // ── Guest mode ───────────────────────────────────────────────────────
  Future<void> setGuestMode(bool isGuest) async => await _storage.write(key: _guestKey, value: isGuest.toString());

  Future<bool> isGuestMode() async {
    final value = await _storage.read(key: _guestKey);
    return value == 'true';
  }

  // ── Device ID ────────────────────────────────────────────────────────
  Future<void> saveDeviceId(String deviceId) async =>
      await _storage.write(key: _deviceIdKey, value: deviceId);

  Future<String?> getDeviceId() async => await _storage.read(key: _deviceIdKey);

  // ── Generic ──────────────────────────────────────────────────────────
  Future<void> write({required String key, required String value}) async =>
      await _storage.write(key: key, value: value);

  Future<String?> read({required String key}) async => await _storage.read(key: key);

  Future<void> delete({required String key}) async => await _storage.delete(key: key);

  Future<void> clearAll() async => await _storage.deleteAll();
}