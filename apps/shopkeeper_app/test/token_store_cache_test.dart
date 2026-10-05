import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';

/// PERFORMANCE — the SecureTokenStore read cache must never become a
/// correctness change.
///
/// The cache removes a platform-channel hop from every API call, but a stale
/// cached token would be an auth bypass, not just a slow read. These tests
/// exist so that risk stays pinned: every mutating path must evict.
///
/// `SecureTokenStore` is the only production store and it talks to
/// `flutter_secure_storage` over a MethodChannel, so the channel is stubbed
/// here with a real in-memory map. That keeps the assertions honest — the
/// cache really is in front of a real read/write/delete pair — while removing
/// the Keystore dependency a unit test must not have.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> backing;
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    backing = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'read':
              return backing[call.arguments['key'] as String];
            case 'write':
              backing[call.arguments['key'] as String] =
                  call.arguments['value'] as String;
              return null;
            case 'delete':
              backing.remove(call.arguments['key'] as String);
              return null;
            case 'readAll':
              return Map<String, String>.from(backing);
            case 'deleteAll':
              backing.clear();
              return null;
            default:
              return null;
          }
        });
    SecureTokenStore.evictAll();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    SecureTokenStore.evictAll();
  });

test('a FAILED write must not leave the token cached in memory', () async {
    // A keystore write can throw: full disk, corrupted keychain, a locked
    // key. If memory were updated first, the caller sees the exception but
    // every later read still returns that token from memory — so the app runs
    // the rest of the session authenticated on a credential that was never
    // persisted, and the next cold start drops the user out with no warning.
    // Ordering storage-before-memory makes the cache a strict subset of what
    // is on disk, so the worst case is a redundant read, never a phantom
    // session.
    var failWrites = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'write') {
            if (failWrites) throw PlatformException(code: 'KEYSTORE_BUSY');
            backing[call.arguments['key'] as String] =
                call.arguments['value'] as String;
            return null;
          }
          switch (call.method) {
            case 'read':
              return backing[call.arguments['key'] as String];
            case 'delete':
              backing.remove(call.arguments['key'] as String);
              return null;
            case 'readAll':
              return Map<String, String>.from(backing);
            case 'deleteAll':
              backing.clear();
              return null;
            default:
              return null;
          }
        });

    // Prove the cache CAN hold a token, so the assertion below is meaningful.
    await SecureTokenStore().saveTokens(
      accessToken: 'good-token',
      refreshToken: 'good-refresh',
    );
    expect(await SecureTokenStore().readAccessToken(), 'good-token');

    // Now a write that fails at the storage layer.
    failWrites = true;
    await expectLater(
      SecureTokenStore().saveTokens(
        accessToken: 'never-persisted',
        refreshToken: 'never-persisted-refresh',
      ),
      throwsA(isA<PlatformException>()),
    );

    // The token that failed to persist must NOT be served from memory, and the
    // previously valid one must still be what the store reports.
    expect(
      await SecureTokenStore().readAccessToken(),
      'good-token',
      reason: 'a failed write must not overwrite the cached token',
    );
    expect(backing['sk_access_token'], 'good-token');
  });


  test('a saved token is readable immediately', () async {
    final store = SecureTokenStore();
    await store.saveTokens(accessToken: 'a1', refreshToken: 'r1');
    expect(await store.readAccessToken(), 'a1');
    expect(await store.readRefreshToken(), 'r1');
  });

  test('re-saving replaces the cached value (no stale token)', () async {
    final store = SecureTokenStore();
    // Token refresh is the real path: the backend rotates the access token
    // mid-session and every later call must carry the NEW one.
    await store.saveTokens(accessToken: 'old', refreshToken: 'r1');
    expect(await store.readAccessToken(), 'old');
    await store.saveTokens(accessToken: 'new', refreshToken: 'r2');
    expect(await store.readAccessToken(), 'new');
    expect(await store.readRefreshToken(), 'r2');
  });

  test('clearAll() evicts memory too — sign-out leaves no token', () async {
    final store = SecureTokenStore();
    await store.saveTokens(accessToken: 'a1', refreshToken: 'r1');
    await store.saveSessionId('s1');
    await store.saveUserId('u1');
    await store.setLoggedIn(true);

    await store.clearAll();

    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
    expect(await store.readSessionId(), isNull);
    expect(await store.readUserId(), isNull);
    expect(await store.isLoggedIn(), isFalse);
  });

  test('a signed-out store stays signed out across repeated reads', () async {
    SecureTokenStore.evictAll();
    final store = SecureTokenStore();
    expect(await store.readAccessToken(), isNull);
    expect(await store.readAccessToken(), isNull);
  });

  test('per-key writes do not leak across keys', () async {
    final store = SecureTokenStore();
    await store.saveSessionId('session-1');
    await store.saveUserId('user-1');
    expect(await store.readSessionId(), 'session-1');
    expect(await store.readUserId(), 'user-1');
  });
}
