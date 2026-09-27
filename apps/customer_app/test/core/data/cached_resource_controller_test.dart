import 'dart:async';

import 'package:hyperlocal_app/core/data/cached_resource_controller.dart';
import 'package:hyperlocal_app/core/data/request_coalescer.dart';
import 'package:hyperlocal_app/core/data/resource.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CachedResourceController', () {
    late RequestCoalescer coalescer;
    late Map<String, CacheEntry<String>> cache;

    CachedResourceController<String> build({
      required Future<String> Function() fetch,
      Duration staleAfter = const Duration(minutes: 2),
    }) {
      return CachedResourceController<String>(
        key: 'resource',
        fetch: fetch,
        coalescer: coalescer,
        staleAfter: staleAfter,
        readCache: () => cache['resource'],
        writeCache: (v) => cache['resource'] = CacheEntry(v, DateTime.now()),
      );
    }

    setUp(() {
      coalescer = RequestCoalescer();
      cache = {};
    });

    test('a warm open with a FRESH cache costs zero requests', () async {
      var calls = 0;
      cache['resource'] = CacheEntry('cached', DateTime.now());
      final c = build(
        fetch: () async {
          calls++;
          return 'fresh';
        },
      );

      await c.warm();

      expect(calls, 0, reason: 'a fresh cache hit is a complete answer');
      expect(c.current, isA<ResourceCached<String>>());
      expect(c.current.dataOrNull, 'cached');
      await c.dispose();
    });

    test(
      'a warm open with a STALE cache publishes cache then revalidates',
      () async {
        var calls = 0;
        cache['resource'] = CacheEntry(
          'old',
          DateTime.now().subtract(const Duration(hours: 1)),
        );
        final c = build(
          fetch: () async {
            calls++;
            return 'fresh';
          },
          staleAfter: const Duration(minutes: 2),
        );

        final states = <Resource<String>>[];
        final sub = c.stream.listen(states.add);
        await c.warm();
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(calls, 1);
        // Cache first (instant paint), then the network answer.
        expect(states.first, isA<ResourceCached<String>>());
        expect(c.current, isA<ResourceData<String>>());
        expect(c.current.dataOrNull, 'fresh');
        await c.dispose();
      },
    );

    test('a cold open with no cache just loads', () async {
      var calls = 0;
      final c = build(
        fetch: () async {
          calls++;
          return 'fresh';
        },
      );

      await c.warm();
      expect(calls, 1);
      expect(c.current.dataOrNull, 'fresh');
      await c.dispose();
    });

    test('two controllers on the same key make one request', () async {
      var calls = 0;
      final completer = Completer<String>();
      Future<String> fetch() {
        calls++;
        return completer.future;
      }

      final a = build(fetch: fetch);
      final b = build(fetch: fetch);

      final fa = a.load();
      final fb = b.load();
      completer.complete('shared');

      await fa;
      await fb;
      expect(calls, 1, reason: 'shared key must share the in-flight request');
      expect(a.current.dataOrNull, 'shared');
      expect(b.current.dataOrNull, 'shared');
      await a.dispose();
      await b.dispose();
    });

    test(
      'a failed refresh keeps the previous data and records the error',
      () async {
        var shouldFail = false;
        final c = build(
          fetch: () async {
            if (shouldFail) throw StateError('offline');
            return 'good';
          },
        );

        await c.load();
        expect(c.current.dataOrNull, 'good');

        shouldFail = true;
        await c.revalidate();

        expect(
          c.current.dataOrNull,
          'good',
          reason: 'a failed refresh must not destroy visible content',
        );
        expect(c.current.hasError, isTrue);
        await c.dispose();
      },
    );

    test(
      'a successful load populates the cache for the next warm open',
      () async {
        final c = build(fetch: () async => 'stored');
        await c.load();
        expect(cache['resource']?.value, 'stored');
        await c.dispose();
      },
    );

    test('states emitted during a cold load start at loading', () async {
      final c = build(fetch: () async => 'v');
      final states = <Resource<String>>[];
      final sub = c.stream.listen(states.add);
      await c.load();
      // A broadcast controller delivers on a later microtask, so the terminal
      // state is not in `states` the instant `load()` returns.
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(states.first, isA<ResourceLoading<String>>());
      expect(states.last, isA<ResourceData<String>>());
      await c.dispose();
    });
  });
}
