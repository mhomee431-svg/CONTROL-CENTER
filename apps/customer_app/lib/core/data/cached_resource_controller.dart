import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'request_coalescer.dart';
import 'resource.dart';

/// A cache entry: the value and WHEN it was stored.
class CacheEntry<T> {
  final T value;
  final DateTime storedAt;
  const CacheEntry(this.value, this.storedAt);
}

/// Turns a plain `Future<T> Function()` into a cached, coalesced,
/// stale-while-revalidate [Resource] stream.
///
/// This is the class that makes "fast data flow" a property of the app rather
/// than something each feature re-implements. It fixes four problems that were
/// being solved badly — or not at all — in every controller:
///
/// 1. **Duplicate requests.** Every load is keyed and run through the shared
///    [RequestCoalescer], so two widgets watching the same resource cause one
///    request, not two.
/// 2. **The blank-screen flash.** A refresh emits [ResourceRefreshing] with the
///    previous data still attached, so pull-to-refresh never blanks content the
///    customer is already reading.
/// 3. **Serving stale data silently.** A cache hit publishes [ResourceCached]
///    with its age, so the UI can disclose staleness instead of passing off old
///    stock as live.
/// 4. **Failure destroying content.** A failed refresh emits [ResourceError]
///    with the previous data retained, so the customer keeps what they had and
///    gains a retry affordance.
///
/// ## Contract with the caller
///
/// [fetch] must be a pure, idempotent read. It is called again on every
/// [revalidate], so anything with a side effect (placing an order) does not
/// belong here. That restriction is exactly what makes auto-revalidation safe.
///
/// ## Cold vs warm
///
/// [load] is a cold open: network, then cache. [warm] is a warm open: the cached
/// value is published IMMEDIATELY so the customer sees the last known data in
/// the first frame, and the network fills in behind it. A cache entry younger
/// than [staleAfter] is treated as a complete answer and is not revalidated at
/// all — that is what makes a warm open cost zero requests.
class CachedResourceController<T> {
  CachedResourceController({
    required this.key,
    required this.fetch,
    required this.readCache,
    required this.writeCache,
    required this.coalescer,
    this.staleAfter = const Duration(minutes: 2),
  });

  /// Identity of this resource. Two controllers with the same key share cache
  /// and coalescing, which is what makes "a screen and a badge" one request.
  final String key;

  final Future<T> Function() fetch;

  /// The cache lookup and store for this resource.
  ///
  /// Plain functions rather than an interface, so a feature can hand in whatever
  /// it already uses (SharedPreferences, an in-memory map, a database) without
  /// this layer knowing about any of them. The type is inferred from the field,
  /// which is why the initializing formals above carry no annotation.
  final CacheEntry<T>? Function() readCache;
  final void Function(T value) writeCache;

  /// The shared coalescer. Public so a caller can construct with the app-wide
  /// instance from `requestCoalescerProvider`.
  final RequestCoalescer coalescer;

  /// How old a cache entry may be before it is revalidated.
  final Duration staleAfter;

  final StreamController<Resource<T>> _controller =
      StreamController<Resource<T>>.broadcast();

  Resource<T> _current = ResourceIdle<T>();

  /// The current state, readable without waiting for a stream event.
  Resource<T> get current => _current;

  /// Updates as state changes.
  ///
  /// Broadcast rather than replay: a listener that subscribes late should read
  /// [current], not be handed every intermediate state the screen scrolled past.
  Stream<Resource<T>> get stream => _controller.stream;

  bool _disposed = false;

  void _emit(Resource<T> next) {
    if (_disposed) return;
    _current = next;
    _controller.add(next);
  }

  /// Cold open: go to the network, then update the cache.
  Future<void> load() async {
    final previous = _current.dataOrNull;
    _emit(_current.toLoading(previous));
    try {
      // Coalesced: if an identical request is already in flight, join it rather
      // than starting a second one.
      final value = await coalescer.run<T>(key, fetch);
      writeCache(value);
      _emit(ResourceData(value));
    } catch (error) {
      // Keep `previous` on screen. A failed refresh must never destroy content.
      _emit(ResourceError(error, previous));
    }
  }

  /// Warm open: publish the cache immediately, then revalidate if it is stale.
  Future<void> warm() async {
    final entry = readCache();
    if (entry == null) return load();

    _emit(ResourceCached(entry.value, entry.storedAt));

    if (DateTime.now().difference(entry.storedAt) >= staleAfter) {
      await load();
    }
  }

  /// Re-reads from cache and revalidates, without the staleness shortcut.
  Future<void> revalidate() => load();

  Future<void> dispose() async {
    _disposed = true;
    await _controller.close();
  }
}

/// The app-wide [RequestCoalescer].
///
/// A single shared instance is the point: coalescing only works if every caller
/// for a given key agrees which request is in flight. One per repository would
/// let two repositories each start their own copy of the same request.
final requestCoalescerProvider = Provider<RequestCoalescer>((ref) {
  return RequestCoalescer();
});
