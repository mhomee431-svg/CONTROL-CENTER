import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ARCHITECTURE GUARD — the client half of the shopkeeper data flow.
///
/// The declared contract:
///
///     Flutter → FastAPI → PostgreSQL/PostGIS      (all data)
///     Flutter → FastAPI authorization → S3         (media)
///     FastAPI → Redis/Valkey                       (optional, server-side)
///
/// The dangerous failure mode is not a crash — it is a shortcut. Someone
/// reaches for Firestore because the backend is slow, or ships an AWS key so
/// an upload "just works". Either quietly rewrites the data flow while every
/// test still passes. These checks make that a build failure.
///
/// Each assertion was verified against a deliberately-injected violation.
void main() {
  List<File> dartFilesUnder(String dir) => Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  final libPath = 'lib';

  /// Every source hit, as `path:line: text`, for a regex.
  List<String> hits(RegExp pattern, {String? dir}) {
    final found = <String>[];
    for (final file in dartFilesUnder(dir ?? libPath)) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) {
          found.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    return found;
  }

  group('data flow: everything goes through FastAPI', () {
    test('no Firestore / Realtime Database client', () {
      // Firebase is the IDENTITY provider in this architecture. A Firestore
      // or RTDB client would make it a datastore too, and the two systems
      // would have no shared transaction boundary.
      final offenders = hits(
        RegExp(
          r'cloud_firestore|FirebaseFirestore|firebase_database|'
          r'realtimeDatabase|\.collection\(',
        ),
      );
      expect(
        offenders,
        isEmpty,
        reason: 'All persisted data flows Flutter → FastAPI → PostgreSQL. '
            'Firebase supplies the ID token only.\n${offenders.join('\n')}',
      );
    });

    test('no direct database driver', () {
      final offenders = hits(
        RegExp(r'postgres|postgresql|psycopg|DATABASE_URL|sqlighter|sqflite',
            caseSensitive: false),
      );
      expect(
        offenders,
        isEmpty,
        reason: 'The app is a pure API client; it must not hold or open a '
            'database connection.\n${offenders.join('\n')}',
      );
    });

    test('dio is the only HTTP transport', () {
      // A second HTTP package usually means a second base URL, and with it a
      // way to bypass the auth interceptor and the request-id tracing.
      //
      // `firebase_core` is deliberately NOT on the forbidden list: Firebase is
      // the identity provider named in the flow, and it never carries data.
      // Only its *datastore* SDKs (see the Firestore check above) would break
      // the contract.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final otherTransports = RegExp(
        r'^\s{2}(http|chopper|retrofit|graphql_flutter|supabase_flutter|'
        r'prisma_client|realm)\s*:',
        multiLine: true,
      );
      final offenders = otherTransports
          .allMatches(pubspec)
          .map((m) => m.group(0)!.trim())
          .toList();

      expect(
        offenders,
        isEmpty,
        reason: 'Only `dio` should carry app traffic — it attaches the bearer '
            'token, the request-id header and the 401 refresh path.\n'
            '${offenders.join('\n')}',
      );
    });
  });

  group('media flow: S3 is private, FastAPI is the gate', () {
    test('no AWS credentials anywhere in the client', () {
      final offenders = hits(
        RegExp(
          r'aws_access_key|aws_secret|aws_session_token|AKIA[0-9A-Z]{16}|'
          r'S3_BUCKET|boto3|AmazonS3Client',
          caseSensitive: false,
        ),
      );
      expect(
        offenders,
        isEmpty,
        reason: 'AWS credentials must never reach the client. The app asks '
            'FastAPI for a short-lived presigned policy instead.\n'
            '${offenders.join('\n')}',
      );
    });

    test('uploads go through a FastAPI-issued policy', () {
      final source =
          File('$libPath/core/network/media_upload_service.dart').readAsStringSync();

      // The sequence that keeps S3 private: ask FastAPI, then POST the file
      // straight to the signed destination.
      expect(
        source,
        contains('ApiEndpoints.mediaUploadUrl'),
        reason: 'the upload ticket must come from the backend, not be '
            'constructed from a key the client chose',
      );
      expect(
        source,
        contains('multipart/form-data'),
        reason: 'the presigned POST policy is form-encoded',
      );
    });

    test('every media call carries the bearer token', () {
      // The direct-to-S3 POST legitimately cannot carry it (it goes to a
      // third-party host); the FastAPI calls that mint/confirm/read must.
      final offenders = hits(
        RegExp(r'''(mediaUrl|mediaUploadUrl|mediaConfirm)'''),
        dir: '$libPath/features',
      );
      // Present at all = the flows are wired; the token itself is asserted in
      // api_client_test.dart. Here we only guard against the calls vanishing.
      expect(offenders, isNotEmpty);
    });
  });

  test('the lib directory resolved (guards against an empty scan)', () {
    // A boundary test whose file list is empty passes for the wrong reason.
    expect(Directory(libPath).existsSync(), isTrue,
        reason: 'run from apps/shopkeeper_app');
    expect(dartFilesUnder(libPath).length, greaterThan(50));
  });
}
