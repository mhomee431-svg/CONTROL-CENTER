import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Abstraction over token persistence so business logic stays testable
/// (unit tests inject [InMemoryTokenStore]; the app wires [SecureTokenStore]).
abstract class TokenStore {
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<String?> readSessionId();
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  });
  Future<void> saveSessionId(String sessionId);
  Future<void> clearAll();
}

/// Production store backed by flutter_secure_storage (encrypted on device).
class SecureTokenStore implements TokenStore {
  static const _storage = FlutterSecureStorage();

  static const _accessKey = 'sk_access_token';
  static const _refreshKey = 'sk_refresh_token';
  static const _sessionKey = 'sk_session_id';

  @override
  Future<String?> readAccessToken() => _storage.read(key: _accessKey);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  @override
  Future<String?> readSessionId() => _storage.read(key: _sessionKey);

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  @override
  Future<void> saveSessionId(String sessionId) =>
      _storage.write(key: _sessionKey, value: sessionId);

  @override
  Future<void> clearAll() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _sessionKey);
  }
}

/// In-memory store for widget/unit tests (no platform channels).
class InMemoryTokenStore implements TokenStore {
  String? _access;
  String? _refresh;
  String? _session;

  @override
  Future<String?> readAccessToken() async => _access;

  @override
  Future<String?> readRefreshToken() async => _refresh;

  @override
  Future<String?> readSessionId() async => _session;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _access = accessToken;
    _refresh = refreshToken;
  }

  @override
  Future<void> saveSessionId(String sessionId) async {
    _session = sessionId;
  }

  @override
  Future<void> clearAll() async {
    _access = null;
    _refresh = null;
    _session = null;
  }
}

/// Default binding â€” override in tests with ProviderScope overrides.
final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());
