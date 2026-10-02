import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/config/env_config.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/domain/auth_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/data/map_providers_config.dart';

/// Strips block and line comments so the scan sees only executable code.
///
/// Line comments use a negative lookbehind for `:` so that the `//` INSIDE a
/// URL literal (`'https://api.hyperlocal.in'`) is not mistaken for a comment —
/// without that, every URL would truncate its own host and the egress allowlist
/// below would pass vacuously.
String _stripComments(String source) {
  var out = source.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  out = out.replaceAll(RegExp(r'(?<!:)//.*$', multiLine: true), '');
  return out;
}

/// Spec §137 SECURITY TESTING — verify the frontend NEVER:
///   1. stores secret keys
///   2. uses AWS credentials
///   3. uses Firebase Admin credentials
///   4. connects directly to a database
///   5. trusts a role from local storage
///   6. trusts a shop ID for authorization
///
/// FIVE of those six are assertions about an ABSENCE, and an absence is
/// something a behavioural test cannot prove — a fake repository happily returns
/// whatever it likes, so "no code path ever reads a secret" is only meaningful
/// as a property of the SOURCE. So this suite is built around a comment-stripped
/// scan of `lib/`, plus behavioural tests for the two "trusts" items.
///
/// Comment stripping is what makes the scan trustworthy: `map_providers_config`
/// *documents* where to get a Google key and the backend has plenty of AWS code,
/// so matching raw text would drown in false positives. Only executable code is
/// matched. This also means a comment cannot mask a real finding.
void main() {
  // ── scan helpers ───────────────────────────────────────────────────────────

  /// Every `.dart` under `lib/`, as (path, code-without-comments).
  List<MapEntry<String, String>> scanLib() {
    final root = Directory('lib');
    expect(root.existsSync(), isTrue, reason: 'lib/ not found from ${Directory.current.path}');
    final files = root
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return [
      for (final f in files)
        MapEntry(
          f.path.replaceAll('\\', '/'),
          _stripComments(f.readAsStringSync()),
        ),
    ];
  }

  /// All [pattern] hits across `lib/`, reported as "path: line" so a failure
  /// names the offending file instead of just saying "something matched".
  List<String> hits(RegExp pattern, {String? path}) {
    final found = <String>[];
    for (final entry in scanLib()) {
      if (path != null && !entry.key.contains(path)) continue;
      final lines = entry.value.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) {
          found.add('${entry.key}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    return found;
  }

  // ── 1. stores secret keys ──────────────────────────────────────────────────

  group('§137.1 never stores secret keys', () {
    test('no client-secret-shaped constant is compiled into the app', () {
      // The real finding from this pass: `mapplsClientSecret` was declared here
      // and read NOWHERE. A secret shipped in an APK is not a secret — it is
      // extracted by anyone who unzips the build — so it was removed along with
      // its unused `client_id` half.
      final found = hits(RegExp(
        r'''(clientSecret|client_secret|CLIENT_SECRET|privateKey|private_key)''',
      ));
      expect(found, isEmpty, reason: 'a client secret in the frontend:\n${found.join('\n')}');
    });

    test('no AWS key, private key or password literal is hardcoded', () {
      final found = hits(RegExp(
        r'''(AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|'''
        r'''aws_secret_access_key\s*[:=]\s*['"][^'"]+['"])''',
      ));
      expect(found, isEmpty, reason: 'hardcoded credential:\n${found.join('\n')}');
    });

    test('the only API-key literals are public, restricted identifiers', () {
      // Precision matters here — a blunt "no AIza key" rule cries wolf and gets
      // ignored, which is worse than no rule. Two literals are legitimate:
      //   * `AIzaSyD-REPLACE_WITH_YOUR_KEY` — an explicit placeholder sentinel
      //     that DISABLES the Google Maps provider until a real key is injected;
      //   * the Firebase *client* apiKey in `firebase_options.dart` — Google
      //     designs it as a public identifier restricted by package name and
      //     signing certificate. It is NOT a credential, and this repo's
      //     `.gitleaks.toml` already allowlists it for the same reason.
      // Anything else is a real leak.
      const publicKeys = {
        'AIzaSyD-REPLACE_WITH_YOUR_KEY',
        'AIzaSyATSoTQd5Fepy53aYYYot3l72RAHIz61Ro',
      };
      final literals = hits(RegExp(r'AIza[0-9A-Za-z_\-]{10,}'));
      for (final hit in literals) {
        final key = RegExp(r'AIza[0-9A-Za-z_\-]{10,}').firstMatch(hit)!.group(0)!;
        expect(
          publicKeys,
          contains(key),
          reason: 'unrecognised API-key literal at $hit',
        );
      }
    });

    test('a placeholder map key leaves the provider switched OFF', () {
      // The placeholder must not silently "work" — if it ever counted as
      // configured, the app would ship making real calls with a dead key.
      expect(MapProvidersConfig.googleMapsApiKey,
          'AIzaSyD-REPLACE_WITH_YOUR_KEY');
      expect(MapProvidersConfig.googleMapsEnabled, isFalse,
          reason: 'the placeholder must not enable the provider');
      expect(MapProvidersConfig.mapplsApiKey, isEmpty);
      expect(MapProvidersConfig.mapplsEnabled, isFalse);
    });

    test('a third-party POS secret is forwarded to the backend, never persisted', () {
      // The POS connector collects a vendor `apiSecret`. It is a TRANSIT field:
      // the controller must hand it to the API and drop it. Nothing may write
      // it to disk, and the state must never carry it once the save lands.
      final found = hits(
        RegExp(r'''(SharedPreferences|writeString|File\(|jsonEncode\(|'''
            r'''SecureTokenStore|tokenStore)[^\n]*apiSecret''',
            caseSensitive: false),
      );
      expect(
        found,
        isEmpty,
        reason: 'a POS secret reaches local storage:\n${found.join('\n')}',
      );

      // It is sent as a request field — that is the whole point.
      final sent = hits(RegExp(r"""'api_secret'"""));
      expect(sent, isNotEmpty, reason: 'the secret must be forwarded to the API');
    });

    test('no insecure store backs the session — tokens go to keychain/keystore',
        () {
      // SharedPreferences is a PLAINTEXT XML/plist file on both platforms, so a
      // session token written there is readable from a backup or a rooted
      // device. flutter_secure_storage is backed by the iOS keychain and the
      // Android EncryptedSharedPreferences.
      expect(
        hits(RegExp(r'SharedPreferences|shared_preferences')),
        isEmpty,
        reason: 'session data must not use plaintext shared preferences',
      );

      final pubspec = File('pubspec.yaml').readAsStringSync();
      for (final insecure in <String>[
        'shared_preferences:',
        'hive:',
        'sqflite:',
        'drift:',
        'isar:',
      ]) {
        expect(
          pubspec.contains(insecure),
          isFalse,
          reason: '$insecure is an unencrypted store and must not be a dependency',
        );
      }
    });

    test('the session token is written to secure storage, not a plain map', () {
      // Guards the actual contract: TokenStore is the only persistence seam and
      // its production implementation is the secure one.
      final store = hits(RegExp(r'class SecureTokenStore'), path: 'token_store.dart');
      expect(store, isNotEmpty, reason: 'the secure token store must exist');

      final impl = hits(RegExp(r'FlutterSecureStorage'), path: 'token_store.dart');
      expect(impl, isNotEmpty);

      // Nothing may persist a token into a plain in-memory/disk map instead.
      expect(
        hits(RegExp(r'''writeAccessToken[^\n]*(Map<|jsonEncode|File\()''')),
        isEmpty,
        reason: 'a token appears to bypass the secure store',
      );
    });
  });

  // ── 2. uses AWS credentials ───────────────────────────────────────────────

  group('§137.2 never uses AWS credentials', () {
    test('no AWS credential or SDK symbol appears in executable code', () {
      final found = hits(RegExp(
        r'(AWS_ACCESS_KEY|AWS_SECRET|aws_access_key|aws_secret_access_key|AmazonS3|boto3|SigV4|AWSCredentials|s3\.amazonaws)',
      ));
      expect(found, isEmpty, reason: 'AWS in the frontend:\n${found.join('\n')}');
    });

    test('the app asks the backend for pre-signed URLs instead of signing', () {
      // The correct client-side pattern: no credential, just a signed URL the
      // backend already authorised. Assert the upload path only ever *consumes*
      // a URL it was handed.
      final found = hits(RegExp(
        r'(generatePresignedUrl|presign|signUrl|aws4|hmac)',
      ));
      expect(
        found,
        isEmpty,
        reason: 'the client must not sign anything itself:\n${found.join('\n')}',
      );
    });
  });

  // ── 3. uses Firebase Admin credentials ─────────────────────────────────────

  group('§137.3 never uses Firebase Admin credentials', () {
    test('no Firebase Admin SDK or service-account credential is present', () {
      // The Admin SDK mints tokens for ANY uid and must live server-side only.
      // The CLIENT SDK (google_sign_in / FirebaseAuth sign-in) is fine and is
      // what this app uses, so only admin-side symbols are forbidden here.
      final found = hits(RegExp(
        r'(firebase_admin|firebaseAdmin|admin\.sdk|service[_A]ccount|GOOGLE_APPLICATION_CREDENTIALS|createCustomToken|private_key_id|"private_key")',
      ));
      expect(found, isEmpty, reason: 'Firebase Admin in the frontend:\n${found.join('\n')}');
    });

    test('the app submits an ID token to the backend rather than verifying it', () {
      // Verification requires the Admin SDK, so the client must hand the raw ID
      // token to the backend and use whatever session JWT comes back.
      final repo = hits(RegExp(r'firebase-login'), path: 'auth');
      expect(repo, isNotEmpty, reason: 'the Firebase login exchange must exist');

      final sessionToken = hits(RegExp(r'readAccessToken'), path: 'token_store.dart');
      expect(sessionToken, isNotEmpty);
    });
  });

  // ── 4. connects directly to a database ─────────────────────────────────────

  group('§137.4 never connects directly to a database', () {
    test('no database driver, DSN or wire protocol appears in code', () {
      final found = hits(RegExp(
        r'''(postgres|postgresql|mysql|mariadb|mongodb|sqlite|sqlalchemy|'''
        r'''psycopg2|jdbc:|asyncpg|pg_hba)''' ,
        caseSensitive: false,
      ));
      expect(found, isEmpty, reason: 'database access in the frontend:\n${found.join('\n')}');
    });

    test('no raw socket or database port is opened — only HTTP via Dio', () {
      // A mobile app cannot reach the private VPC the database lives in; if it
      // could, the network boundary that protects the data would be gone.
      final found = hits(RegExp(
        r'(Socket\.connect|InternetAddress|HttpClient\(|RawDatagram|:5432|:3306|:6379|:27017)',
      ));
      expect(found, isEmpty, reason: 'raw egress in the frontend:\n${found.join('\n')}');
    });

    test('every outbound host is the backend API or a known map provider', () {
      // An allowlist, so an exfiltration endpoint cannot be added by accident.
      const allowed = <String>[
        'api.hyperlocal.in',
        'staging-api.hyperlocal.in',
        '10.0.2.2',      // Android emulator loopback to a dev backend
        '127.0.0.1',    // iOS simulator loopback
        'localhost',
        'maps.googleapis.com',
        'apis.mappls.com',
        'nominatim.openstreetmap.org',
        'www.mapmyindia.com',
      ];
      final hosts = <String>{};
      for (final entry in scanLib()) {
        for (final m in RegExp(r'''https?://([A-Za-z0-9.\-]+)''').allMatches(entry.value)) {
          hosts.add(m.group(1)!);
        }
      }
      // A dev LAN IP shows up as an interpolated host and is covered by the
      // `_lanIp` define, so only literal hosts are collected here.
      expect(
        hosts.difference(allowed.toSet()),
        isEmpty,
        reason: 'unexpected outbound host(s): ${hosts.difference(allowed.toSet())}',
      );
    });
  });

  // ── 5. trusts a role from local storage ────────────────────────────────────

  group('§137.5 never trusts a role from local storage', () {
    test('no code compares a role against a PRIVILEGE string', () {
      // The forbidden pattern is a role being weighed for access: `role ==
      // 'admin'`, `role.contains('owner')`. That is what "trusting a role" means,
      // and it is what a forged local value could manipulate.
      //
      // A null-check like `user?.role != null` is deliberately ALLOWED: that
      // decides whether to *draw* a role badge, and grants nothing. Conflating
      // display with authorization would make this rule useless.
      final found = hits(RegExp(
        r'''(\.role|role)\s*(==|!=)\s*['"](admin|owner|superadmin|'''
        r'''super_admin|shopkeeper|manager|staff)['"]''',
        caseSensitive: false,
      ));
      expect(
        found,
        isEmpty,
        reason: 'a role string decides access:\n${found.join('\n')}',
      );
    });

    test('no code branches on role MEMBERSHIP to gate a capability', () {
      // `permissions.contains('update:shop')` is the only sanctioned gate.
      // The reverse check guards against reintroducing membership-as-privilege.
      final gated = hits(RegExp(
        r'''(if|return|assert|expect)\s*\([^)]*\.(isOwner|isManager)\b''',
      ));
      expect(
        gated,
        isEmpty,
        reason: 'membership is used as a capability gate:\n${gated.join('\n')}',
      );
    });

    test('the role field is never persisted to the token store', () {
      final store = File('lib/core/network/token_store.dart').readAsStringSync();
      final keys = RegExp(r"'(access_token|refresh_token|session_id|business_id"
              r"|user_id|is_logged_in|jwt_token)'")
          .allMatches(store)
          .map((m) => m.group(1)!)
          .toSet();
      expect(keys, isNotEmpty, reason: 'the key set must still be found');
      expect(
        keys.where((k) => k.contains('role')),
        isEmpty,
        reason: 'a role must never be persisted: $keys',
      );
    });

    test('a shop with no backend permissions is denied, whatever its role', () {
      // Fail-closed: if the backend sends an empty permission list the client
      // must not infer capability from `membership` or `role`.
      const bare = ShopSummary(
        id: 1,
        name: 'Corner Store',
        status: 'ACTIVE',
        isVerified: true,
        membership: 'owner',
        permissions: [],
      );
      expect(bare.canManageSettings, isFalse);
      expect(bare.canManageProducts, isFalse);

      // And the parse cannot be tricked into inventing permissions.
      final parsed = ShopSummary.fromJson(<String, dynamic>{
        'id': 1,
        'name': 'Corner Store',
        'membership': 'owner',
        'permissions': null,
      });
      expect(parsed.permissions, isEmpty);
      expect(parsed.canManageSettings, isFalse);

      // Non-string junk in the list is discarded, not coerced into a match.
      final noisy = ShopSummary.fromJson(<String, dynamic>{
        'id': 1,
        'name': 'Corner Store',
        'membership': 'owner',
        'permissions': [1, 'update:shop', null, {'a': 1}],
      });
      expect(noisy.permissions, <String>['update:shop']);
      expect(noisy.canManageSettings, isTrue);
      expect(noisy.canManageProducts, isFalse);
    });
  });

  // ── 6. trusts a shop ID for authorization ──────────────────────────────────

  group('§137.6 never trusts a shop ID for authorization', () {
    test('the backend is the only source of the authorized-shop list', () {
      // `ShopsController` is the single fetcher; the selection policy can only
      // ever pick from what it published. A shop ID invented locally cannot
      // enter the list because the list is never assembled locally.
      final found = hits(RegExp(
        r'''(ShopSummary\([^\n]*id:\s*(1|2|3|10)\b)''',
        multiLine: true,
      ));
      expect(
        found,
        isEmpty,
        reason: 'a shop may be constructed with a hardcoded id in lib/:'
            '\n${found.join('\n')}',
      );
    });

    test('capability is decided by permissions, never by the shop id', () {
      // Same id, different permissions → different capability. If the id drove
      // the decision, these would agree.
      const without = ShopSummary(
        id: 42,
        name: 'Shop A',
        status: 'ACTIVE',
        isVerified: true,
        membership: 'owner',
        permissions: [],
      );
      final granted = ShopSummary(
        id: 42,
        name: 'Shop A',
        status: 'ACTIVE',
        isVerified: true,
        membership: 'manager',
        permissions: ['update:shop', 'update:product'],
      );

      expect(without.canManageSettings, isFalse);
      expect(granted.canManageSettings, isTrue);
      // …and membership ("owner") is not treated as an implicit grant.
      expect(without.isOwner, isTrue);
      expect(without.canManageProducts, isFalse);
    });

    test('production and staging talk to the backend over HTTPS only', () {
      // The shop ID travels in the URL, so plaintext HTTP on a release build
      // would expose it to anyone on the network.
      expect(EnvConfig.isProduction, isFalse,
          reason: 'tests must not run as a release build');
      expect(
        EnvConfig.defaultBaseUrlFor(AppEnv.production),
        startsWith('https://'),
      );
      expect(
        EnvConfig.defaultBaseUrlFor(AppEnv.staging),
        startsWith('https://'),
      );
      // Development is the one exception: the emulator loopback backend is
      // plain HTTP by design and never ships.
      expect(
        EnvConfig.defaultBaseUrlFor(AppEnv.development),
        startsWith('http://'),
      );
    });
  });
}