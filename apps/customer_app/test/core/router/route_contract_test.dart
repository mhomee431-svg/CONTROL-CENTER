import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal_app/core/router/app_router.dart';

/// Route contract: locks the router table against drift in BOTH directions.
///
/// 1. The raw `path:` declarations extracted from `app_router.dart` must equal
///    exactly the expected set below — adding or removing a route forces this
///    test to be updated deliberately.
/// 2. Every literal `context.push(...)` / `context.go(...)` target in `lib/`
///    must resolve against the full (parent+child) route patterns — a push to
///    an undefined route (the old `push('/otp')` bug) fails here.
void main() {
  /// Raw `path:` values as written in the router source (nested routes are
  /// declared relative to their parent).
  const declaredPaths = {
    '/splash',
    '/location-permission',
    '/select-location',
    '/coming-soon',
    '/search-results-by-pin/:pin',
    '/product/:id',
    'shops',
    '/shop/:id',
    '/directions',
    '/profile/edit',
    '/profile/addresses',
    '/my-favorites',
    '/recently-viewed',
    '/settings',
    '/privacy',
    '/terms',

    '/help',
    '/orders',
    '/order/:id',
    '/login',
    '/otp',
    '/register',
    '/welcome',
    '/onboarding',
    '/map-picker',
    '/',
    '/search',
    'results',
    '/saved',
    '/notifications',
    '/profile',
  };

  /// Fully-qualified patterns (parent + child) used to validate nav targets.
  const fullPatterns = {
    '/splash',
    '/location-permission',
    '/select-location',
    '/coming-soon',
    '/search-results-by-pin/:pin',
    '/product/:id',
    '/product/:id/shops',
    '/shop/:id',
    '/directions',
    '/profile/edit',
    '/profile/addresses',
    '/my-favorites',
    '/recently-viewed',
    '/settings',
    '/privacy',
    '/terms',

    '/help',
    '/orders',
    '/order/:id',
    '/login',
    '/otp',
    '/register',
    '/welcome',
    '/onboarding',
    '/map-picker',
    '/',
    '/search',
    '/search/results',
    '/saved',
    '/notifications',
    '/profile',
  };

  final routerFile = File('lib/core/router/app_router.dart');
  final routerSource = routerFile.readAsStringSync();
  final extracted = RegExp(r"path: '([^']+)'")
      .allMatches(routerSource)
      .map((m) => m.group(1)!)
      .toSet();

  test('router declares exactly the expected route set', () {
    expect(extracted, declaredPaths);
  });

  test('every navigation call site targets a declared route', () {
    // Literal string targets only; dynamic targets (e.g. promotion banners
    // pushing a server-provided URL) are validated by their owner screens.
    final pushRe = RegExp(r"context\.(?:push|go)\(\s*'([^']+)'");
    final failures = <String>[];

    final libDir = Directory('lib');
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match in pushRe.allMatches(source)) {
        var target = match.group(1)!;
        // Strip query string / fragment: '/directions?shopId=x' -> '/directions'.
        target = target.split('?').first.split('#').first;
        // Replace interpolated segments: '${...}' -> placeholder segment.
        target = target.replaceAll(RegExp(r'\$\{[^}]*\}'), '\u0000');
        if (!_matchesAnyPattern(target, fullPatterns)) {
          failures.add('${entity.path}: $target');
        }
      }
    }

    expect(
      failures,
      isEmpty,
      reason: 'Navigation targets with no matching route: $failures',
    );
  });

  test('real router resolves every declared route', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final GoRouter router = container.read(routerProvider);

    for (final pattern in fullPatterns) {
      // Turn '/product/:id' into a concrete probe URI.
      final probe = pattern
          .replaceAll(RegExp(r':[A-Za-z0-9_]+'), 'probe')
          .replaceAll('\u0000', 'probe');
      final matchList = router.configuration.findMatch(Uri.parse(probe));
      expect(
        matchList.matches,
        isNotEmpty,
        reason: 'GoRouter failed to match /$probe (pattern $pattern)',
      );
    }

    // Sanity: an unknown route must NOT match, proving the matcher above is
    // actually discriminating and not a tautology.
    final unknown = router.configuration.findMatch(
      Uri.parse('/definitely-not-a-route'),
    );
    expect(unknown.matches, isEmpty);
  });
}

bool _matchesAnyPattern(String target, Set<String> patterns) {
  for (final pattern in patterns) {
    if (_matches(target, pattern)) return true;
  }
  return false;
}

bool _matches(String target, String pattern) {
  final escaped = pattern
      .split('/')
      .map((segment) {
        if (segment.startsWith(':')) return '[^/]+';
        return RegExp.escape(segment).replaceAll('\u0000', '[^/]+');
      })
      .join('/');
  final regex = RegExp('^$escaped\$');
  return regex.hasMatch(target);
}
