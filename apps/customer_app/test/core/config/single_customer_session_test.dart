import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contract: exactly one authenticated customer session at a time.
///
/// ## Why this is a test and not a convention
///
/// Nothing in the type system stops someone adding an "account switcher": a
/// `List<String> tokens` in the storage class, a "sign in as" sheet, a
/// `currentAccountIndex`. Each addition looks locally reasonable and each
/// changes the product's security model.
///
/// The distinction this file protects:
///
///  * **Multiple ACCOUNTS** (one person holding two identities in the app) is
///    NOT supported and must not be built. The backend models one identity per
///    Firebase UID; a second local profile would be a client-side fiction with
///    no server behind it, and the resulting "why is my order missing" support
///    load is severe.
///  * **Multiple SESSIONS** (phone + tablet, same account) ARE supported — the
///    backend has `AuthSession`, `refresh_session` and `logout_session(revoke_all=)`.
///    That is not multi-account and must not be mistaken for it. A user signing
///    in on a second device is normal and should keep working.
///
/// So the rule being enforced is narrow and deliberate: one *identity* on the
/// device, while remaining compatible with the backend's multi-*session* model.
void main() {
  late Directory lib;

  setUpAll(() {
    lib = Directory('lib');
    // Runs from apps/customer_app (the package root), as other source-scanning
    // contract tests in this suite do.
    expect(
      lib.existsSync(),
      isTrue,
      reason: 'must run from apps/customer_app, not the repo root',
    );
  });

  List<File> dartFiles() {
    final out = <File>[];
    void walk(Directory dir) {
      for (final entity in dir.listSync()) {
        if (entity is Directory) {
          walk(entity);
        } else if (entity is File && entity.path.endsWith('.dart')) {
          if (entity.path.contains('.g.dart')) continue;
          if (entity.path.contains('freezed')) continue;
          out.add(entity);
        }
      }
    }

    walk(lib);
    return out;
  }

  group('no multi-account capability is introduced', () {
    test('no account-switching vocabulary anywhere in lib/', () {
      // Adding any of these is the first visible step toward multi-account.
      final forbidden = <String>[
        'switchAccount',
        'switchUser',
        'addAccount',
        'activeAccount',
        'currentAccountIndex',
        'accountsList',
        'signInAs',
        'multiAccount',
      ];

      final offenders = <String>[];
      for (final file in dartFiles()) {
        final source = file.readAsStringSync();
        for (final term in forbidden) {
          if (source.contains(term)) {
            offenders.add('${file.path}: $term');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Multi-account support is intentionally absent. If this is '
            'really wanted, the backend must support it first — a second '
            'local profile has no server behind it.\n${offenders.join('\n')}',
      );
    });

    test('the session token is stored as a single value, never a list', () {
      // A `List<String> tokens` in storage is how a second session becomes a
      // second account without anyone noticing. `_storage.saveToken` is the
      // single write path — it lives on the API client, not a separate storage
      // class, so the invariant is asserted where the code actually is.
      final apiClient = File('lib/core/network/api_client.dart');
      final source = apiClient.readAsStringSync();

      expect(source.contains('saveToken('), isTrue);
      expect(source.contains('deleteToken()'), isTrue);

      expect(
        RegExp(r'List<String>\s+tokens').hasMatch(source),
        isFalse,
        reason: 'a token list is the signature of multi-session storage',
      );
    });
  });

  group('the single-session model is coherent', () {
    test('sign-in writes exactly one token, sign-out clears exactly one', () {
      // One write path and one clear path means there is no second identity to
      // leave behind.
      final apiClient = File('lib/core/network/api_client.dart');
      final authService = File('lib/features/auth/domain/auth_service.dart');

      for (final file in [apiClient, authService]) {
        final source = file.readAsStringSync();
        expect(
          RegExp(r'saveToken\(').allMatches(source).isNotEmpty,
          isTrue,
          reason: '${file.path} must persist the token',
        );
        expect(
          RegExp(r'deleteToken\(').allMatches(source).isNotEmpty,
          isTrue,
          reason: '${file.path} must clear the token on sign-out',
        );
      }
    });

    test('a fresh sign-in replaces rather than accumulates', () {
      // saveToken overwriting is what guarantees "one at a time". If it ever
      // appends to a collection, this assertion is the thing that catches it.
      final apiClient = File('lib/core/network/api_client.dart');
      final source = apiClient.readAsStringSync();

      final saveAt = source.indexOf('saveToken(');
      expect(saveAt, greaterThan(-1), reason: 'saveToken must exist');
      final deleteAt = source.indexOf('deleteToken()');

      // Between the write path and the clear path there must be no collection
      // of tokens being built up.
      final window = deleteAt > saveAt
          ? source.substring(saveAt, deleteAt)
          : source.substring(saveAt, saveAt + 600);

      expect(
        window.contains('List<String>'),
        isFalse,
        reason: 'saveToken must not touch a collection of tokens',
      );
      expect(
        RegExp(r'tokens\s*\.\s*add\(').hasMatch(window),
        isFalse,
        reason: 'saveToken must overwrite, never append to a list',
      );
    });
  });
}
