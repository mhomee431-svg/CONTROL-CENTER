import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Abstraction over token persistence so business logic stays testable
/// (unit tests inject [InMemoryTokenStore]; the app wires [SecureTokenStore]).
abstract class TokenStore {
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<String?> readSessionId();
  Future<String?> readBusinessId();
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  });
  Future<void> saveSessionId(String sessionId);
  Future<void> saveBusinessId(String businessId);
  Future<void> clearAll();
}

/// Production store backed by flutter_secure_storage (encrypted on device).
class SecureTokenStore implements TokenStore {
  static const _storage = FlutterSecureStorage();

  static const _accessKey = 'sk_access_token';
  static const _refreshKey = 'sk_refresh_token';
  static const _sessionKey = 'sk_session_id';
  static const _businessIdKey = 'sk_business_id';

  @override
  Future<String?> readAccessToken() => _storage.read(key: _accessKey);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  @override
  Future<String?> readSessionId() => _storage.read(key: _sessionKey);

  @override
  Future<String?> readBusinessId() => _storage.read(key: _businessIdKey);

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
  Future<void> saveBusinessId(String businessId) =>
      _storage.write(key: _businessIdKey, value: businessId);

  @override
  Future<void> clearAll() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _sessionKey);
    await _storage.delete(key: _businessIdKey);
  }
}

/// In-memory store for widget/unit tests (no platform channels).
class InMemoryTokenStore implements TokenStore {
  InMemoryTokenStore({
    String? accessToken,
    String? refreshToken,
    String? sessionId,
    this._businessId,
  })  : _access = accessToken,
        _refresh = refreshToken,
        _session = sessionId;

  String? _access;
  String? _refresh;
  String? _session;
  String? _businessId;

  @override
  Future<String?> readAccessToken() async => _access;

  @override
  Future<String?> readRefreshToken() async => _refresh;

  @override
  Future<String?> readSessionId() async => _session;

  @override
  Future<String?> readBusinessId() async => _businessId;

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
  Future<void> saveBusinessId(String businessId) async {
    _businessId = businessId;
  }

  @override
  Future<void> clearAll() async {
    _access = null;
    _refresh = null;
    _session = null;
    _businessId = null;
  }
}

/// Default binding â€” override in tests with ProviderScope overrides.
final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());
