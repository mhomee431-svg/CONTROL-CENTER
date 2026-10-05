import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_app/core/observability/crash_reporter.dart';
import 'package:hyperlocal_app/core/observability/performance_observer.dart';

void main() {
  group('spans measure what actually happened', () {
    test('a sync span records a duration and returns the value', () {
      final observer = PerformanceObserver(reportToTimeline: false)..reset();

      final result = observer.span('work', () => 42);

      expect(result, 42);
      expect(observer.records, hasLength(1));
      expect(observer.records.single.name, 'work');
    });

    test('an async span measures the WHOLE await, not just the first tick', () async {
      final observer = PerformanceObserver(reportToTimeline: false)..reset();

      await observer.spanAsync('search', () async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return 'ok';
      });

      // The regression this guards: an observer that stops the clock before the
      // first await reports ~0ms for a search that took 40ms, which is how a
      // "search latency" dashboard ends up green while customers wait.
      expect(
        observer.records.single.duration.inMilliseconds,
        greaterThanOrEqualTo(30),
        reason: 'the span must include the awaited time',
      );
    });

    test('a span is still recorded when the body throws', () {
      final observer = PerformanceObserver(reportToTimeline: false)..reset();

      expect(
        () => observer.span('boom', () => throw StateError('x')),
        throwsStateError,
      );
      // Otherwise a crash erases the timing of the operation that caused it —
      // exactly the span you want when diagnosing it.
      expect(observer.records, hasLength(1));
    });

    test('an async span is still recorded when the body throws', () async {
      final observer = PerformanceObserver(reportToTimeline: false)..reset();

      await expectLater(
        observer.spanAsync('boom', () async => throw StateError('x')),
        throwsStateError,
      );
      expect(observer.records, hasLength(1));
    });
  });

  group('the buffer is bounded', () {
    test('old records are dropped rather than growing without end', () {
      // An unbounded span log is a memory leak wearing a monitoring costume —
      // and a leak in the thing meant to detect leaks.
      final observer = PerformanceObserver(
        maxEntries: 5,
        reportToTimeline: false,
      )..reset();

      for (var i = 0; i < 50; i++) {
        observer.record('op$i', const Duration(milliseconds: 1));
      }

      expect(observer.records, hasLength(5));
      expect(
        observer.records.first.name,
        'op45',
        reason: 'the OLDEST must be dropped first',
      );
      expect(observer.records.last.name, 'op49');
    });

    test('the crash context list is bounded separately and tighter', () {
      final observer = PerformanceObserver(
        maxEntries: 200,
        reportToTimeline: false,
      )..reset();

      for (var i = 0; i < 100; i++) {
        observer.record('op$i', const Duration(milliseconds: 1));
      }

      // Unbounded history would defeat the purpose: a crash context nobody can
      // read is the same as no context.
      expect(observer.recentSpans.length, lessThanOrEqualTo(20));
      expect(observer.recentSpans.last, 'op99');
    });
  });

  group('counters answer safely before any data', () {
    test('a fresh observer reports no frames rather than dividing by zero', () {
      final observer = PerformanceObserver(reportToTimeline: false)..reset();

      expect(observer.totalFrames, 0);
      expect(observer.jankRate, 0);
      expect(
        observer.averageRasterTime,
        isNull,
        reason:
            'a mean of no samples is unknown, not zero — zero would read as '
            'a healthy app that has never rendered',
      );
    });
  });

  group('a crash carries the context it happened in', () {
    test('the report includes the recent spans', () {
      // The point of the whole feature: a stack says which line threw, not
      // what the customer was doing when it did.
      final observer = PerformanceObserver(reportToTimeline: false)..reset();
      final sink = InMemoryCrashSink();
      final reporter = CrashReporter(observer: observer, sink: sink);

      observer.record('search_submit', const Duration(milliseconds: 120));
      observer.record('map_render', const Duration(milliseconds: 300));
      reporter.capture(StateError('boom'), StackTrace.current);

      expect(sink.reports, hasLength(1));
      final report = sink.reports.single;
      expect(report.recentSpans, contains('search_submit'));
      expect(report.recentSpans, contains('map_render'));
      expect(report.source, 'manual');
    });

    test('the crash is retained even with no sink attached', () {
      // In release there is no console to read, so in-memory retention is the
      // only reason a crash is diagnosable at all.
      final reporter = CrashReporter(
        observer: PerformanceObserver(reportToTimeline: false),
      )..reset();

      reporter.capture(StateError('boom'), StackTrace.current);

      expect(reporter.lastCrash, isNotNull);
      expect(reporter.crashCount, 1);
      expect(reporter.lastCrash!.error, isA<StateError>());
    });

    test('a throwing sink does not become a second crash', () {
      // A reporter that throws while reporting an error turns one failure into
      // two, at the worst possible moment.
      final reporter = CrashReporter(
        observer: PerformanceObserver(reportToTimeline: false),
        sink: _ThrowingCrashSink(),
      );

      expect(
        () => reporter.capture(StateError('boom'), StackTrace.current),
        returnsNormally,
      );
      expect(reporter.crashCount, 1);
    });

    test('crashes are counted, not just retained', () {
      final reporter = CrashReporter(
        observer: PerformanceObserver(reportToTimeline: false),
      )..reset();

      reporter.capture(StateError('a'), StackTrace.current);
      reporter.capture(StateError('b'), StackTrace.current);

      expect(reporter.crashCount, 2);
      expect(reporter.lastCrash!.error, isA<StateError>());
    });
  });

  group('nothing leaves the device by default', () {
    test('capturing a crash with no sink attached is inert and safe', () {
      // The whole "no excessive SDKs" constraint, enforced: there is no network
      // call anywhere in this path unless a sink is supplied.
      final reporter = CrashReporter(
        observer: PerformanceObserver(reportToTimeline: false),
      )..reset();

      expect(
        () => reporter.capture(StateError('boom'), StackTrace.current),
        returnsNormally,
      );
      expect(reporter.crashCount, 1);
    });
  });
}

class _ThrowingCrashSink implements CrashSink {
  @override
  void submit(CrashReport report) => throw StateError('sink is broken');
}
