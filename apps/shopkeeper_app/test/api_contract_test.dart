import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// API CONTRACT — the Shopkeeper app must speak the backend's REAL vocabulary.
///
/// Every other suite in this repository exercises behaviour through a fake
/// repository, and a fake returns whatever it likes. That means the whole app
/// could be perfectly green while calling endpoints the backend does not
/// serve, or serving a response envelope it cannot parse — a broken integration
/// that no unit test would ever catch, and that only surfaces as a timeout on
/// a real device.
///
/// This file closes that gap WITHOUT a live server: it reads the backend's
/// committed OpenAPI document and holds every endpoint the app references to
/// it. A renamed or deleted backend route now fails the build instead of
/// failing in production.
///
/// It also pins the app's own stated namespace rule ("the Shopkeeper app
/// exclusively consumes `/shopkeeper/*`"), with the shared-platform exceptions
/// listed and justified rather than left as drift.
void main() {
  group('API CONTRACT — endpoints exist in the backend contract', () {
    final specFile = File('../../packages/api_contracts/openapi.json');
    late Map<String, dynamic> specPaths;

    setUpAll(() {
      expect(
        specFile.existsSync(),
        isTrue,
        reason:
            'the OpenAPI document is the contract; if it moved, update '
            'the path here rather than deleting the check',
      );
      final decoded =
          jsonDecode(specFile.readAsStringSync()) as Map<String, dynamic>;
      specPaths = (decoded['paths'] as Map).cast<String, dynamic>();
      expect(
        specPaths.length,
        greaterThan(100),
        reason: 'sanity: the contract really parsed and has the routes',
      );
    });

    /// Every endpoint literal the app can call.
    Set<String> appEndpoints() {
      final source = File('lib/core/network/api_endpoints.dart')
          .readAsStringSync();
      return RegExp(r"'(/api/v1/[^']*)'")
          .allMatches(source)
          .map((m) => m.group(1)!)
          .toSet();
    }

    /// Normalises a concrete path to the comparison shape: OpenAPI
    /// `{shop_id}` placeholders and Dart `$id` interpolation both collapse
    /// to `{}`, so `'/shops/$id'` equals `'/shops/{shop_id}'`.
    String normalize(String path) {
      // Drop any query string: OpenAPI paths never carry one, but a few app
      // endpoints append `?shop_id=` to scope a legacy route.
      var out = path.split('?').first;
      // Collapse Dart interpolation (`$id` / `${id}`) to `{}`. Built by
      // concatenating a `$` char code so no escaping survives the string
      // literal, and `[$]` keeps it inside a character class.
      const dollar = '\$';
      out = out.replaceAllMapped(
        RegExp('[$dollar][{]?[A-Za-z_][A-Za-z0-9_]*[}]?'),
        (_) => '{}',
      );
      // Collapse OpenAPI placeholders (`{shop_id}`) to `{}` as well.
      out = out.replaceAllMapped(RegExp(r'\{[^}]+\}'), (_) => '{}');
      return out;
    }

    test('every app endpoint matches a real backend route', () {
      final shapes = specPaths.keys.map(normalize).toSet();
      // A shared PREFIX, not a route. `posJob` is only ever used to build
      // `posJobDetail` / `posJobRetry`; the bare `/pos/jobs` collection is not
      // an endpoint the backend serves (the spec has only `/jobs/{job_id}` and
      // `/jobs/{job_id}/retry`). Such prefixes must be declared here — an
      // UNLISTED one is a real "the app calls a route that does not exist".
      const knownPrefixes = <String>{
        '/api/v1/shopkeeper/pos/jobs', // base for posJobDetail / posJobRetry
      };

      final offenders = <String>[];
      for (final raw in appEndpoints()) {
        if (knownPrefixes.contains(raw)) continue;
        if (!shapes.contains(normalize(raw))) offenders.add(raw);
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'These endpoints are called by the app but do not exist in '
            'packages/api_contracts/openapi.json. Either the backend renamed '
            'the route (update both) or the app calls something that does not '
            'exist — it will time out on a device and never fail a unit '
            'test.\n${offenders.join('\n')}',
      );
    });

    test('the Shopkeeper namespace rule holds, with justified exceptions', () {
      // `api_endpoints.dart` states the app "exclusively consumes the isolated
      // /shopkeeper/* module — never the customer /auth/* or discovery
      // routes". That is a claim; this makes it enforced. The exceptions are
      // deliberately enumerated so a NEW cross-namespace call must be argued
      // for in review instead of slipping in silently.
      const justified = <String, String>{
        '/api/v1/profile':
            'the signed-in user profile — /profile, not '
            'shop-scoped',
        '/api/v1/categories':
            'platform-wide catalog taxonomy: a shopkeeper '
            'files a product under the SAME category a customer browses',
        '/api/v1/locations/pincode/': 'address autocomplete during shop setup',
        '/api/v1/media/':
            'presigned upload/confirm for shop + product images; '
            'AWS credentials never reach the client',
      };

      final unexpected = <String>[];
      for (final raw in appEndpoints()) {
        if (raw.startsWith('/api/v1/shopkeeper/')) continue;
        if (justified.keys.any((prefix) => raw.startsWith(prefix))) continue;
        unexpected.add(raw);
      }

      expect(
        unexpected,
        isEmpty,
        reason:
            'A new endpoint escapes the /shopkeeper/* namespace without a '
            'recorded justification. Add it to the justified map with WHY it '
            'is shared, or route it through the shopkeeper module.\n'
            '${unexpected.join('\n')}',
      );
    });

    test('the app never calls the CUSTOMER auth module directly', () {
      // `/auth/*` belongs to the customer app. Calling it from Shopkeeper
      // would bypass the shopkeeper-scoped auth service the backend reuses
      // deliberately, and would couple two apps' sessions.
      final customerAuth = appEndpoints()
          .where((e) => e.startsWith('/api/v1/auth/'))
          .toList();

      expect(
        customerAuth,
        isEmpty,
        reason:
            'Use /shopkeeper/auth/*, never the customer /auth/* module.\n'
            '${customerAuth.join('\n')}',
      );
    });

    test('the auth seam the app depends on is really in the contract', () {
      // The ownership chain is only as real as the routes behind it: exchange
      // once, then use the backend's own token from then on.
      for (final route in const [
        '/api/v1/shopkeeper/auth/firebase-login',
        '/api/v1/shopkeeper/auth/me',
        '/api/v1/shopkeeper/auth/refresh',
        '/api/v1/shopkeeper/auth/logout',
      ]) {
        expect(
          specPaths.containsKey(route),
          isTrue,
          reason:
              'the auth chain needs $route and the contract does not have '
              'it — the session cannot be established',
        );
      }
    });
  });
}
