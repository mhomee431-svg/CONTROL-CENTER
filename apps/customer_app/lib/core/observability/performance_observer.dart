import 'dart:collection';
import 'dart:developer' as developer;

import 'package:flutter/scheduler.dart';

/// Lightweight, dependency-free performance instrumentation.
///
/// ## Why no third-party SDK
/// ------------------------
/// Every area this covers is already measurable with tools that ship inside the
/// Flutter SDK: `dart:developer` Timeline emits spans DevTools reads directly,
/// and `SchedulerBinding.addTimingsCallback` reports the real build/raster
/// time of every frame. A crash reporter would add a dependency, a network call
/// and a privacy surface for something that is mostly a durable ring buffer
/// plus a hook.
///
/// So this is built on the platform, and the *sink* is left pluggable. Nothing
/// leaves the device unless a sink is supplied, which today none is.
///
/// ## Why the buffer is bounded
/// ---------------------------
/// An unbounded log of spans is a memory leak wearing a monitoring costume —
/// and a memory leak is one of the things this is meant to detect. [maxEntries]
/// caps it and drops the oldest first. The buffer is a fixed cost the app pays
/// whether or not anything ever goes wrong.
///
/// ## What "latency" means here
/// --------------------------
/// Client-side, always. A search is slow for the customer if the spinner is up,
/// and that includes debounce and request time. The server's own number is a
/// different series; conflating them makes the client look fine while the
/// customer waits.
class PerformanceObserver {
  PerformanceObserver({this.maxEntries = 200, this.reportToTimeline = true});

  /// Hard cap on retained records. The cost of monitoring is fixed, not a
  /// function of session length.
  final int maxEntries;

  /// Emit to `dart:developer` Timeline. Near-free, and what makes the spans
  /// visible in DevTools without any exporter.
  final bool reportToTimeline;

  static final PerformanceObserver instance = PerformanceObserver();

  final Queue<PerformanceRecord> _records = Queue<PerformanceRecord>();
  final List<String> _crashMarkers = <String>[];

  bool _frameTimingsHooked = false;

  /// Frames slower than this on build or raster are counted as jank.
  ///
  /// 16.7ms is one frame at 60Hz. 100ms is the threshold Android itself uses
  /// for "frozen". Both are tracked so a mild stutter and a real freeze can be
  /// told apart rather than averaged into one meaningless number.
  static const Duration jankThreshold = Duration(milliseconds: 17);
  static const Duration frozenThreshold = Duration(milliseconds: 100);

  int _totalFrames = 0;
  int _jankyFrames = 0;
  int _frozenFrames = 0;
  Duration _totalBuild = Duration.zero;
  Duration _totalRaster = Duration.zero;

  // ── Counters ──────────────────────────────────────────────────────────────
  int get totalFrames => _totalFrames;
  int get jankyFrames => _jankyFrames;
  int get frozenFrames => _frozenFrames;
  Duration get totalBuildTime => _totalBuild;
  Duration get totalRasterTime => _totalRaster;

  /// Mean raster time per frame, or null before any frame is seen.
  Duration? get averageRasterTime => _totalFrames == 0
      ? null
      : Duration(microseconds: _totalRaster.inMicroseconds ~/ _totalFrames);

  /// Share of frames that missed the budget, 0..1.
  double get jankRate => _totalFrames == 0 ? 0 : _jankyFrames / _totalFrames;

  /// Retained records, oldest first.
  List<PerformanceRecord> get records => List.unmodifiable(_records);

  /// Recent span names, newest last. Attached to a crash so a report says what
  /// the app was doing rather than just that it broke.
  List<String> get recentSpans => List.unmodifiable(_crashMarkers);

  /// Starts capturing per-frame build/raster timings.
  ///
  /// Safe to call repeatedly. Uses `addTimingsCallback`, the supported API for
  /// this in profile and release builds — `PerformanceOverlay` is a debug-only
  /// visual aid and would be useless in production.
  void hookFrameTimings() {
    if (_frameTimingsHooked) return;
    _frameTimingsHooked = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _totalFrames++;
      final build = timing.buildDuration;
      final raster = timing.rasterDuration;
      _totalBuild += build;
      _totalRaster += raster;

      final worst = build > raster ? build : raster;
      if (worst >= frozenThreshold) {
        _frozenFrames++;
        _jankyFrames++;
      } else if (worst >= jankThreshold) {
        _jankyFrames++;
      }
    }
  }
  // ── Spans ─────────────────────────────────────────────────────────────────

  /// Runs [body], recording how long it took under [name].
  ///
  /// Works for both sync and async bodies: an async one is awaited, so the
  /// recorded duration is the whole operation and not just the part before the
  /// first await. Getting that wrong is how a "search latency" number ends up
  /// measuring 4ms of scheduling instead of the customer's actual wait.
  Future<T> spanAsync<T>(String name, Future<T> Function() body) async {
    final started = DateTime.now();
    if (reportToTimeline) {
      developer.Timeline.startSync(name);
    }
    try {
      return await body();
    } finally {
      _record(name, DateTime.now().difference(started));
      if (reportToTimeline) {
        developer.Timeline.finishSync();
      }
    }
  }

  /// Synchronous counterpart to [spanAsync].
  T span<T>(String name, T Function() body) {
    final started = DateTime.now();
    if (reportToTimeline) {
      developer.Timeline.startSync(name);
    }
    try {
      return body();
    } finally {
      _record(name, DateTime.now().difference(started));
      if (reportToTimeline) {
        developer.Timeline.finishSync();
      }
    }
  }

  /// Records a duration measured elsewhere, e.g. one that started in a
  /// different layer.
  void record(String name, Duration duration, {Map<String, Object?>? data}) {
    _record(name, duration, data: data);
    if (reportToTimeline) {
      developer.Timeline.instantSync(
        name,
        arguments: data?.map((k, v) => MapEntry(k, '$v')),
      );
    }
  }

  void _record(String name, Duration duration, {Map<String, Object?>? data}) {
    _records.addLast(
      PerformanceRecord(
        name: name,
        duration: duration,
        at: DateTime.now(),
        data: data,
      ),
    );
    // Bounded: drop the OLDEST so a long session cannot grow this without end.
    while (_records.length > maxEntries) {
      _records.removeFirst();
    }
    _crashMarkers.add(name);
    // A separate, tighter bound: this exists to give a crash recent context,
    // and unbounded history would defeat that by being unusable.
    while (_crashMarkers.length > 20) {
      _crashMarkers.removeAt(0);
    }
  }

  /// Clears everything. For tests and for a "user opts out" path.
  void reset() {
    _records.clear();
    _crashMarkers.clear();
    _totalFrames = 0;
    _jankyFrames = 0;
    _frozenFrames = 0;
    _totalBuild = Duration.zero;
    _totalRaster = Duration.zero;
  }
}

/// One measured operation.
class PerformanceRecord {
  const PerformanceRecord({
    required this.name,
    required this.duration,
    required this.at,
    this.data,
  });

  final String name;
  final Duration duration;
  final DateTime at;
  final Map<String, Object?>? data;

  @override
  String toString() => '$name ${duration.inMilliseconds}ms';
}
