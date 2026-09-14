import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Abstraction over token persistence so business logic stays testable
/// (unit tests inject [InMemoryTokenStore]; the app wires [SecureTokenStore]).
abstract class TokenStore {
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<String?> readSessionId();
  Future<String?> readBusinessId();
  Future<String?> readUserId();
  Future<bool> isLoggedIn();
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  });
  Future<void> saveSessionId(String sessionId);
  Future<void> saveBusinessId(String businessId);
  Future<void> saveUserId(String userId);
  Future<void> setLoggedIn(bool value);
  Future<void> clearAll();
}

/// Production store backed by flutter_secure_storage (encrypted on device).
class SecureTokenStore implements TokenStore {
  static const _storage = FlutterSecureStorage();

  static const _accessKey = 'sk_access_token';
  static const _refreshKey = 'sk_refresh_token';
  static const _sessionKey = 'sk_session_id';
  static const _businessIdKey = 'sk_business_id';
  // User-specified keys for login session tracking
  static const _jwtTokenKey = 'jwt_token';
  static const _userIdKey = 'user_id';
  static const _isLoggedInKey = 'is_logged_in';

  @override
  Future<String?> readAccessToken() => _storage.read(key: _accessKey);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  @override
  Future<String?> readSessionId() => _storage.read(key: _sessionKey);

  @override
  Future<String?> readBusinessId() => _storage.read(key: _businessIdKey);

  @override
  Future<String?> readUserId() => _storage.read(key: _userIdKey);

  @override
  Future<bool> isLoggedIn() async {
    final value = await _storage.read(key: _isLoggedInKey);
    return value == 'true';
  }

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
    // Mirror the access token to the user-specified key
    await _storage.write(key: _jwtTokenKey, value: accessToken);
  }

  @override
  Future<void> saveSessionId(String sessionId) =>
      _storage.write(key: _sessionKey, value: sessionId);

  @override
  Future<void> saveBusinessId(String businessId) =>
      _storage.write(key: _businessIdKey, value: businessId);

  @override
  Future<void> saveUserId(String userId) =>
      _storage.write(key: _userIdKey, value: userId);

  @override
  Future<void> setLoggedIn(bool value) =>
      _storage.write(key: _isLoggedInKey, value: value.toString());

  @override
  Future<void> clearAll() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _sessionKey);
    await _storage.delete(key: _businessIdKey);
    await _storage.delete(key: _jwtTokenKey);
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _isLoggedInKey);
  }
}

/// In-memory store for widget/unit tests (no platform channels).
class InMemoryTokenStore implements TokenStore {
  InMemoryTokenStore({
    String? accessToken,
    String? refreshToken,
    String? sessionId,
    this._businessId,
    this._userId,
    this._isLoggedIn = false,
  })  : _access = accessToken,
        _refresh = refreshToken,
        _session = sessionId;

  String? _access;
  String? _refresh;
  String? _session;
  String? _businessId;
  String? _userId;
  bool _isLoggedIn;

  @override
  Future<String?> readAccessToken() async => _access;

  @override
  Future<String?> readRefreshToken() async => _refresh;

  @override
  Future<String?> readSessionId() async => _session;

  @override
  Future<String?> readBusinessId() async => _businessId;

  @override
  Future<String?> readUserId() async => _userId;

  @override
  Future<bool> isLoggedIn() async => _isLoggedIn;

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
  Future<void> saveUserId(String userId) async {
    _userId = userId;
  }

  @override
  Future<void> setLoggedIn(bool value) async {
    _isLoggedIn = value;
  }

  @override
  Future<void> clearAll() async {
    _access = null;
    _refresh = null;
    _session = null;
    _businessId = null;
    _userId = null;
    _isLoggedIn = false;
  }
}

/// Default binding — override in tests with ProviderScope overrides.
final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());
