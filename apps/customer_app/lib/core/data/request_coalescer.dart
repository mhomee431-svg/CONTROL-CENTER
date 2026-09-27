import 'dart:async';

import 'package:flutter/foundation.dart';

/// Coalesces identical in-flight reads into a single network call.
///
/// WHY THIS EXISTS
/// ---------------
/// Without it, one user intent produces several requests. The common paths are:
///
///  * a Riverpod provider rebuilds and refetches;
///  * two widgets watch the same resource and both kick off a load;
///  * a list screen and a badge both read the same unread count;
///  * the user taps Retry while the original request is still in flight.
///
/// Each of those is a real duplicated GET: wasted battery, wasted bandwidth,
/// wasted server work, and — worst for the customer — N responses racing to
/// update the same state, so the last one to land wins even if it is the
/// STALEST. That last point is a correctness bug, not just a performance one.
///
/// The rule: while a request identified by [key] is in flight, any caller
/// asking for the same key joins that request instead of starting a new one. The
/// first caller's [fetch] runs; everyone gets the same result.
///
/// ## Why the key is a String and not a typed object
///
/// Callers build the key from the request shape (`'GET /products?page=2'`), so
/// the coalescer needs no generics and no knowledge of any feature. It also means
/// a mistyped key can never silently collide across two different models, since
/// the path is part of it.
///
/// ## Not a cache
///
/// This deduplicates CONCURRENT work only. Once a request completes, the result
/// is forgotten; a later request for the same key starts fresh. Caching
/// completed results is a separate, explicit decision (see `ApiCache`), because
/// silently serving a stale list is a much bigger decision than sharing an
/// in-flight request.
class RequestCoalescer {
  RequestCoalescer();

  final Map<String, _InFlight> _inFlight = {};

  /// Number of requests currently in flight. Exposed for tests and diagnostics.
  @visibleForTesting
  int get inFlightCount => _inFlight.length;

  /// Runs [fetch] for [key], or joins the identical request already running.
  ///
  /// [fetch] is invoked AT MOST ONCE per concurrent batch for a given [key].
  /// Every caller receives the same outcome, including the same error — which
  /// is why an error is cached for the duration of the request too: otherwise
  /// N callers would each get a different, separately-logged failure.
  Future<T> run<T>(String key, Future<T> Function() fetch) {
    final existing = _inFlight[key];
    if (existing != null) {
      return _guard(existing.future.then((value) => value as T));
    }

    final controller = Completer<T>();
    _inFlight[key] = _InFlight(controller.future);

    // Deliberately not `await`: the completer is completed by the callbacks, and
    // awaiting here would keep this frame on the stack for the whole request.
    fetch().then(
      (value) {
        _complete(key, () => controller.complete(value));
      },
      onError: (Object error, StackTrace stack) {
        _complete(key, () => controller.completeError(error, stack));
      },
    );

    return _guard(controller.future);
  }

  /// Registers a no-op error listener on [future] and returns it unchanged.
  ///
  /// Dart reports a future as an "unhandled error" if it completes with an error
  /// at a moment when it has no listener. A caller that creates a coalesced
  /// request and attaches its handler a statement or two later — a prefetch, or
  /// a test doing `final a = run(...); final b = run(...); await expectLater(a)`
  /// — leaves that window open, and the zone then raises an uncaught exception
  /// that fails a completely unrelated test.
  ///
  /// A second, do-nothing listener closes the window without changing the
  /// future's value or error, so the real caller still sees the failure.
  Future<T> _guard<T>(Future<T> future) {
    future.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return future;
  }

  /// Removes [key] from the in-flight set, then runs [finish].
  ///
  /// The entry is cleared BEFORE the completer is completed. Completing first
  /// would let a listener synchronously call `run` again for the same key and
  /// receive the in-flight future that is completing right now — a promise
  /// resolved to itself, which deadlocks.
  void _complete(String key, void Function() finish) {
    _inFlight.remove(key);
    finish();
  }
}

class _InFlight {
  final Future<dynamic> future;
  const _InFlight(this.future);
}
