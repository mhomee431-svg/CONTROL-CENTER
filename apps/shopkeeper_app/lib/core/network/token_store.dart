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

  // ── PERFORMANCE: in-memory cache over encrypted storage ────────────────
  //
  // Every repository reads the access token before every API call, and
  // `FlutterSecureStorage.read` is a platform-channel hop into Keystore/Keychain.
  // On a screen that fires several calls in parallel (dashboard loads alerts +
  // notifications + products) that is the same encrypted read many times per
  // frame budget, for a value that cannot change between calls.
  //
  // The cache is a pure read-through: the FIRST read still hits secure storage
  // (so a cold start reads exactly what was persisted, and an app that was
  // killed and relaunched cannot invent a token), and every write/clear evicts
  // the affected key. That keeps the security property unchanged — the token
  // is never held any longer or less protected than it already was, since it
  // was already resident in the process for the whole session — while removing
  // the repeated platform hop.
  static final Map<String, String?> _cache = <String, String?>{};

  static Future<String?> _read(String key) async {
    if (_cache.containsKey(key)) return _cache[key];
    final value = await _storage.read(key: key);
    _cache[key] = value;
    return value;
  }

  /// Storage FIRST, memory second.
  ///
  /// Writing the cache before the storage write succeeds leaves memory holding
  /// a token that was never persisted: if the keystore write throws (full disk,
  /// corrupted keystore, a locked keychain), the caller sees the exception but
  /// every later read still returns that token from memory. The app then runs
  /// the whole session authenticated on a credential that does not exist on
  /// disk, and the next cold start drops the user out with no explanation.
  ///
  /// Ordering it this way makes memory a strict subset of what is persisted, so
  /// the worst case is a redundant read, never a phantom session.
  static Future<void> _write(String key, String value) async {
    await _storage.write(key: key, value: value);
    _cache[key] = value;
  }

  /// Drops every cached key. Called on sign-out so the next process (and the
  /// next reader) can never see a stale token from memory.
  static void evictAll() => _cache.clear();

  @override
  Future<String?> readAccessToken() => _read(_accessKey);

  @override
  Future<String?> readRefreshToken() => _read(_refreshKey);

  @override
  Future<String?> readSessionId() => _read(_sessionKey);

  @override
  Future<String?> readBusinessId() => _read(_businessIdKey);

  @override
  Future<String?> readUserId() => _read(_userIdKey);

  @override
  Future<bool> isLoggedIn() async {
    final value = await _read(_isLoggedInKey);
    return value == 'true';
  }

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _write(_accessKey, accessToken);
    await _write(_refreshKey, refreshToken);
    // Mirror the access token to the user-specified key
    await _write(_jwtTokenKey, accessToken);
  }

  @override
  Future<void> saveSessionId(String sessionId) =>
      _write(_sessionKey, sessionId);

  @override
  Future<void> saveBusinessId(String businessId) =>
      _write(_businessIdKey, businessId);

  @override
  Future<void> saveUserId(String userId) => _write(_userIdKey, userId);

  @override
  Future<void> setLoggedIn(bool value) =>
      _write(_isLoggedInKey, value.toString());

  @override
  Future<void> clearAll() async {
    // Evict FIRST: if a delete throws, memory must not keep serving a token
    // the caller believes they just signed out of.
    evictAll();
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
  }) : _access = accessToken,
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
