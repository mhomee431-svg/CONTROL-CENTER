import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Locks the credential-hygiene contract for the app.
///
/// WHY A TEST AND NOT JUST A REVIEW
/// --------------------------------
/// Everything asserted here is a property that was true on the day it was
/// written and can silently stop being true six months later: someone adds a
/// service-account JSON to `assets/`, pastes an AWS key into a Dart file "just
/// to test locally", or replaces a build-time placeholder with a real key. A
/// test is the only thing that notices.
///
/// The rule being enforced: the CLIENT ships public identifiers and nothing
/// more. Server-side authority — Firebase Admin, AWS, database passwords —
/// belongs to the backend, where it never reaches a customer's device.
void main() {
  /// Source files a credential could hide in. Generated output is excluded
  /// because it is only ever a copy of what is already checked here.
  List<File> dartSources() =>
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

  group('no server-side authority ships in the app', () {
    test('no Firebase Admin service-account key is committed', () {
      // A `service_account` JSON carries a `private_key`, which would let
      // anyone holding the app admin-auth as the whole customer base — mint
      // tokens, read every user's data. Unlike an API key this is NOT safely
      // publishable, so its absence is worth enforcing rather than assuming.
      final offenders = <String>[];
      for (final dir in ['lib', 'assets', 'android', 'ios']) {
        if (!Directory(dir).existsSync()) continue;
        for (final entity in Directory(dir).listSync(recursive: true)) {
          if (entity is! File) continue;
          final path = entity.path.replaceAll(r'\', '/');
          if (path.contains('/build/') || path.contains('/.dart_tool/')) continue;
          if (!path.endsWith('.json')) continue;
          final content = entity.readAsStringSync();
          if (content.contains('"type": "service_account"') ||
              content.contains('"private_key"')) {
            offenders.add(path);
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'Admin credentials must live on the backend, never in the app',
      );
    });

    test('no AWS access key or secret is hardcoded', () {
      // `AKIA…` is an access-key id and the giveaway for a leaked pair.
      final offenders = <String>[];
      for (final file in dartSources()) {
        final content = file.readAsStringSync();
        if (RegExp(r'AKIA[0-9A-Z]{16}').hasMatch(content)) {
          offenders.add(file.path);
        }
        if (_matches(content, RegExp(r'aws_secret_access_key\s*[:=]'))) {
          offenders.add(file.path);
        }
      }
      expect(offenders, isEmpty, reason: 'AWS credentials must not be in the app');
    });

    test('no database password or credential-bearing URL is hardcoded', () {
      // A bare host is not a secret (the app legitimately knows its API URL);
      // a URL carrying a password is.
      final offenders = <String>[];
      for (final file in dartSources()) {
        final content = file.readAsStringSync();
        if (_matches(content, RegExp(r'(postgres|mysql|mongodb)://'))) {
          offenders.add(file.path);
        }
        if (_matches(content, RegExp(r'(db|database|db_)password\s*[:=]'))) {
          offenders.add(file.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'database credentials belong to the backend',
      );
    });
  });

  group('build-time injection is intact', () {
    test('the Maps key stays a build-time placeholder, not a real key', () {
      // Committing a real key would leak it to every fork of the repository.
      const manifest = 'android/app/src/main/AndroidManifest.xml';
      if (File(manifest).existsSync()) {
        expect(
          File(manifest).readAsStringSync(),
          contains(r'${MAPS_API_KEY}'),
          reason: 'the manifest must reference the build-time placeholder',
        );
      }
      const plist = 'ios/Runner/Info.plist';
      if (File(plist).existsSync()) {
        expect(
          File(plist).readAsStringSync(),
          contains(r'$(MAPS_API_KEY)'),
          reason: 'Info.plist must reference the build-time placeholder',
        );
      }
    });
  });
}

/// Whether [content] contains a [pattern] followed by an actual VALUE.
///
/// The bare keyword alone is not a finding: a config key name, a comment
/// explaining that passwords belong on the server, or a JSON field name all
/// match `password\s*[:=]` without containing a secret. Requiring a non-empty,
/// non-whitespace run after the separator is what separates "this names a
/// credential" from "this IS a credential" — and it keeps the guard from
/// failing on its own source code, which mentions these words constantly.
bool _matches(String content, RegExp pattern) {
  final match = pattern.firstMatch(content);
  if (match == null) return false;
  final value = RegExp(r'\S+').firstMatch(content.substring(match.end))?.group(0);
  if (value == null || value.isEmpty) return false;

  // Obvious placeholders are not credentials.
  const placeholders = ['null', 'none', 'true', 'false', 'your_', 'xxx', '***'];
  final lower = value.toLowerCase();
  return !placeholders.any(lower.startsWith);
}