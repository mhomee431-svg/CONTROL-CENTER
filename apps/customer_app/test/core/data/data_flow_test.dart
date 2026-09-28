import 'dart:async';

import 'package:hyperlocal_app/core/data/request_coalescer.dart';
import 'package:hyperlocal_app/core/data/resource.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RequestCoalescer', () {
    late RequestCoalescer coalescer;

    setUp(() => coalescer = RequestCoalescer());

    test(
      'runs the fetch once for concurrent callers of the same key',
      () async {
        var calls = 0;
        final completer = Completer<int>();
        Future<int> fetch() {
          calls++;
          return completer.future;
        }

        // Three callers, one intent. Without coalescing this is three requests.
        final a = coalescer.run('GET /products', fetch);
        final b = coalescer.run('GET /products', fetch);
        final c = coalescer.run('GET /products', fetch);

        expect(calls, 1, reason: 'the network call must be made exactly once');
        expect(coalescer.inFlightCount, 1);

        completer.complete(42);
        expect(await a, 42);
        expect(await b, 42);
        expect(await c, 42);
      },
    );

    test('different keys are NOT coalesced', () async {
      var calls = 0;
      Future<int> fetch() async {
        calls++;
        return calls;
      }

      await coalescer.run('GET /products?page=1', fetch);
      await coalescer.run('GET /products?page=2', fetch);
      expect(calls, 2, reason: 'page 2 is a genuinely different request');
    });

    test(
      'a completed request is not cached — a later call refetches',
      () async {
        var calls = 0;
        Future<int> fetch() async => ++calls;

        expect(await coalescer.run('k', fetch), 1);
        expect(await coalescer.run('k', fetch), 2);
        expect(
          coalescer.inFlightCount,
          0,
          reason: 'the in-flight entry must be released on completion',
        );
      },
    );

    test('an error reaches every caller and still releases the key', () async {
      var calls = 0;
      Future<int> fetch() async {
        calls++;
        throw StateError('boom');
      }

      final a = coalescer.run('k', fetch);
      final b = coalescer.run('k', fetch);

      await expectLater(a, throwsStateError);
      await expectLater(b, throwsStateError);
      expect(calls, 1);
      expect(coalescer.inFlightCount, 0);
    });

    test('after an error, a retry is allowed and actually refetches', () async {
      var calls = 0;
      Future<int> fetch() async {
        calls++;
        if (calls == 1) throw StateError('first fails');
        return 7;
      }

      await expectLater(coalescer.run('k', fetch), throwsStateError);
      expect(await coalescer.run('k', fetch), 7);
    });
  });

  group('Resource', () {
    test('a cold open is loading, not refreshing', () {
      const r = ResourceIdle<int>();
      expect(
        r.isLoading,
        isFalse,
        reason: 'idle is "not started", not "working"',
      );
      expect(r.dataOrNull, isNull);
      expect(r.toLoading(), isA<ResourceLoading<int>>());
    });

    test('a refresh keeps the previous data visible', () {
      const r = ResourceData<int>(5);
      final refreshing = r.toLoading();
      expect(refreshing, isA<ResourceRefreshing<int>>());
      expect(
        refreshing.dataOrNull,
        5,
        reason: 'refresh must not blank what the customer is reading',
      );
      expect(refreshing.isLoading, isTrue);
    });

    test('a cache hit is reported as stale, fresh data is not', () {
      final cached = ResourceCached<int>(1, DateTime(2026));
      const fresh = ResourceData<int>(1);
      expect(cached.isStale, isTrue);
      expect(cached.dataOrNull, 1);
      expect(fresh.isStale, isFalse);
    });

    test('an error after data retains the data', () {
      const err = ResourceError<int>('nope', 9);
      expect(err.dataOrNull, 9, reason: 'failure must not destroy content');
      expect(err.hasError, isTrue);
      expect(err.error, 'nope');
    });
  });
}
