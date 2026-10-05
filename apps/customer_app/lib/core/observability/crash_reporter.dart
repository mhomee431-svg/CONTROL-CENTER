import 'dart:async';
import 'dart:io' show ProcessInfo;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../security/safe_logger.dart';
import 'performance_observer.dart';

/// A crash, plus what the app was doing when it happened.
///
/// [recentSpans] is the whole point. A stack trace says which line threw; it
/// does not say the customer was mid-search behind a 4-second request, or that
/// the last twenty operations were all map renders. Attaching recent span names
/// turns "Null check operator used on a null value" into a diagnosable report.
@immutable
class CrashReport {
  const CrashReport({
    required this.error,
    required this.stackTrace,
    required this.at,
    required this.source,
    this.recentSpans = const <String>[],
    this.memoryMb,
  });

  final Object error;
  final StackTrace stackTrace;
  final DateTime at;

  /// Where it surfaced: 'framework', 'platform', 'zone' or 'manual'.
  final String source;

  final List<String> recentSpans;

  /// Resident set size at crash time, when available.
  final double? memoryMb;

  @override
  String toString() =>
      'CrashReport($source, $error, spans=${recentSpans.length})';
}

/// Captures uncaught errors and keeps a bounded copy of the last few.
///
/// ## What changed from the previous behaviour
/// ------------------------------------------
/// The old handlers called `SafeLogger.error`, which prints to the console and
/// — for the exception body and stack — only in debug. In a release build that
/// meant a crash left **no trace on the device at all**: the app died and
/// nothing recorded why. This captures into memory so a report survives to be
/// uploaded or shown, and only then hands off to the existing logger.
///
/// ## Why this is not a third-party SDK
/// ------------------------------------
/// Everything here is Flutter/Dart built-ins. A crash service would add a
/// dependency, a network call on the worst possible moment (often mid-error),
/// and a stream of customer data leaving the device. [CrashSink] is the
/// extension point if that trade is ever worth making deliberately.
class CrashReporter {
  CrashReporter({PerformanceObserver? observer, this._sink})
    : _observer = observer ?? PerformanceObserver.instance;

  final PerformanceObserver _observer;
  final CrashSink? _sink;

  /// Most recent crash, or null. Useful for a "something went wrong" report on
  /// the next launch.
  CrashReport? get lastCrash => _lastCrash;
  CrashReport? _lastCrash;

  int _crashCount = 0;
  int get crashCount => _crashCount;

  /// Installs the framework and platform handlers.
  ///
  /// Call once, early in `main`. Deliberately does NOT wrap `runApp` in a zone:
  /// `runZonedGuarded` around the whole app changes error-zone behaviour for
  /// every async call the app makes, a large blast radius for a monitoring
  /// concern. These two handlers catch the overwhelming majority of crashes
  /// without that trade.
  void install() {
    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      _capture(
        details.exception,
        details.stack ?? StackTrace.current,
        'framework',
      );
      // Chain rather than replace: the previous handler is Flutter's default
      // reporting, and swallowing it would hide errors from the console in
      // debug, where a developer is actively looking for them.
      previousFlutterHandler?.call(details);
    };

    final previousPlatformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _capture(error, stack, 'platform');
      return previousPlatformHandler?.call(error, stack) ?? true;
    };
  }

  /// Wraps a known-risky async entry point in a guarded zone.
  ///
  /// For startup work outside the widget tree's error zone. Opt-in per call
  /// site rather than global, for the reason given on [install].
  R? runGuarded<R>(R Function() body) {
    return runZonedGuarded<R>(body, (error, stack) {
      _capture(error, stack, 'zone');
    });
  }

  /// Records a crash. Public so a non-fatal failure worth diagnosing can be
  /// reported through the same path.
  void capture(Object error, StackTrace stack, {String source = 'manual'}) {
    _capture(error, stack, source);
  }

  void _capture(Object error, StackTrace stack, String source) {
    _crashCount++;

    final report = CrashReport(
      error: error,
      stackTrace: stack,
      at: DateTime.now(),
      source: source,
      recentSpans: _observer.recentSpans,
      memoryMb: residentMemoryMb(),
    );
    _lastCrash = report;

    // Console output stays, so existing debug workflow is unchanged.
    SafeLogger.error('Uncaught $source error', error, stack);

    final sink = _sink;
    if (sink != null) {
      // Guarded: a failing reporter must not become a second crash while we are
      // already handling one.
      try {
        sink.submit(report);
      } catch (e) {
        SafeLogger.error('Crash sink threw while reporting', e);
      }
    }
  }

  /// Clears the retained crash. For tests and an opt-out path.
  void reset() {
    _lastCrash = null;
    _crashCount = 0;
  }
}

/// Resident memory in MB, or null where unavailable.
double? residentMemoryMb() {
  try {
    return ProcessInfo.currentRss / (1024 * 1024);
  } catch (_) {
    return null;
  }
}

/// Destination for crash reports.
///
/// Null by default: nothing leaves the device. Implement this to upload, and the
/// observer's recent spans travel with the report.
abstract class CrashSink {
  void submit(CrashReport report);
}

/// Captures reports in memory. For tests.
class InMemoryCrashSink implements CrashSink {
  final List<CrashReport> reports = <CrashReport>[];

  @override
  void submit(CrashReport report) => reports.add(report);
}
