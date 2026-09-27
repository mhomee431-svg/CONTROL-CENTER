import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The three connection states the customer is told about.
///
/// Tri-state rather than a bool because "we just lost the network" and "we
/// think we are back but have not proven it yet" are genuinely different
/// situations. A bool collapses both into `true`, and the UI then silently
/// stops warning while every request is still failing — the customer is told
/// things are fine at exactly the moment they are not.
enum ConnectivityStatus {
  /// Nothing is known yet — the first probe has not answered.
  ///
  /// This state exists purely so the app does not have to lie during startup.
  /// Defaulting to [online] would flash a healthy banner and let a screen full
  /// of requests fire before anyone knew whether the device had a network;
  /// defaulting to [offline] would flash a scary red banner at every launch,
  /// including on a perfectly good connection. Neither is true, so neither is
  /// shown: the UI stays neutral until a real answer arrives.
  ///
  /// It is deliberately not "reconnecting" — nothing has been lost yet, so
  /// there is nothing to be reconnecting from.
  unknown,

  /// Connected and verified by a successful reachability probe.
  online,

  /// Confirmed to have no usable network transport.
  offline,

  /// The transport is back, but no request has succeeded yet, so real
  /// connectivity is unproven. Requests may still fail.
  reconnecting,
}

/// Monitors network connectivity status and exposes a stream of connection
/// states.
class ConnectivityService {
  final Connectivity _connectivity;

  /// Overridable clock so the reconnecting timeout is testable without
  /// waiting in real time.
  final DateTime Function() _now;

  /// How long [ConnectivityStatus.reconnecting] may last before the service
  /// gives up and reports [ConnectivityStatus.offline].
  ///
  /// A transport can report "connected" (a captive portal, a dead uplink, a
  /// VPN that dropped its tunnel) while nothing is actually reachable. Probing
  /// is the only way to tell, and without a timeout the UI would sit in
  /// "Reconnecting…" forever.
  static const Duration reconnectTimeout = Duration(seconds: 12);

  /// Broadcast so several listeners (the banner, request guards, background
  /// refreshes) can observe the same state.
  ///
  /// A single-subscription `async*` generator could only ever feed one caller,
  /// and a controller that the state mutators never `add` to would silently
  /// miss every change driven by real traffic — which is exactly how a screen
  /// ends up stuck on "Reconnecting…" after the request that should have ended
  /// it succeeded.
  final StreamController<ConnectivityStatus> _controller =
      StreamController<ConnectivityStatus>.broadcast();

  /// Fires when [reconnectTimeout] elapses without a successful request.
  ///
  /// Without this the deadline in [_applyTransportResults] would only be
  /// evaluated the next time the platform happened to emit a transport event,
  /// so a captive portal that reports "connected" once and then goes quiet
  /// would leave the UI claiming "Reconnecting…" indefinitely.
  Timer? _reconnectDeadline;

  /// Starts as [ConnectivityStatus.unknown] — see the enum docs for why
  /// starting `online` would be a claim the service cannot yet support.
  ConnectivityStatus _status = ConnectivityStatus.unknown;
  DateTime? _transportLostAt;
  bool _disposed = false;

  /// The plugin's own event stream, folded into the same state machine.
  ///
  /// Held as a field (not chained into [onStatusChanged]) so that transport
  /// events keep arriving even when nobody is currently listening to the public
  /// status stream. Chaining it would mean a disconnect that happened while no
  /// UI was mounted went entirely unnoticed until the next listener appeared.
  ///
  /// Started lazily by [listenToTransport] rather than in the constructor:
  /// subscribing to the plugin's `EventChannel` touches the platform
  /// messenger, which throws "Binding has not yet been initialized" in a plain
  /// unit test. Deferring it keeps [ConnectivityService] constructible
  /// anywhere, including in tests that only exercise the state machine.
  StreamSubscription<List<ConnectivityResult>>? _transportSub;

  ConnectivityService(this._connectivity, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// Begins folding platform transport events into the status stream.
  ///
  /// Idempotent, and called by `connectivityStatusProvider`. Safe to skip
  /// entirely: a service that is only ever driven through [checkConnectivity]
  /// and the request callbacks works perfectly well without it.
  void listenToTransport() {
    if (_disposed || _transportSub != null) return;
    // Errors from the platform channel (an unsupported platform, a missing
    // plugin) must not crash the app or wedge the stream, so they are swallowed
    // here rather than propagated into [onStatusChanged] and on to the UI.
    _transportSub = _connectivity.onConnectivityChanged.listen(
      _applyTransportResults,
      onError: (Object _) {},
    );
  }

  ConnectivityStatus get status => _status;

  /// True only when connectivity has actually been proven.
  ///
  /// [ConnectivityStatus.unknown] is `false`: before the first probe there is
  /// no proof of anything, and reporting `true` is the optimistic claim this
  /// class exists to avoid.
  bool get isConnected => _status == ConnectivityStatus.online;

  /// Back-compat view of [status] for existing boolean consumers.
  ///
  /// `reconnecting` reports `false`: from the customer's point of view,
  /// unproven connectivity is not connectivity, and claiming otherwise is the
  /// same failure this enum exists to prevent.
  bool get isOnline => isConnected;

  /// Stream that emits on every meaningful state change.
  ///
  /// Emits the current value immediately so a new listener is never left
  /// waiting, then every subsequent change regardless of what caused it.
  Stream<ConnectivityStatus> get onStatusChanged async* {
    yield _status;
    yield* _controller.stream;
  }

  /// Back-compat bool stream.
  Stream<bool> get onConnectivityChanged =>
      onStatusChanged.map((s) => s == ConnectivityStatus.online);

  Future<bool> checkConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    _applyTransportResults(results);
    return isConnected;
  }

  /// Folds a transport report into a [ConnectivityStatus].
  ///
  /// Exposed (and pure) so the mapping can be unit-tested directly rather
  /// than only through the plugin.
  @visibleForTesting
  ConnectivityStatus applyTransportResults(List<ConnectivityResult> results) =>
      _applyTransportResults(results);

  /// Called by the network layer when a request definitively succeeds.
  ///
  /// This is what promotes `reconnecting` to `online`. Connectivity is only
  /// *proven* by traffic actually working, never by the transport flag alone.
  void confirmReachable() {
    _cancelReconnectDeadline();
    _setStatus(ConnectivityStatus.online);
    _transportLostAt = null;
  }

  /// Called when a request fails for network reasons.
  void noteRequestFailure() {
    if (_status == ConnectivityStatus.offline) return;
    // A request failed while the transport claimed to be up: that is a
    // partial/real connectivity problem, not a clean offline.
    _setStatus(ConnectivityStatus.offline);
    _transportLostAt ??= _now();
  }

  ConnectivityStatus _applyTransportResults(List<ConnectivityResult> results) {
    final hasTransport = results.any((r) => r != ConnectivityResult.none);

    if (!hasTransport) {
      _cancelReconnectDeadline();
      _setStatus(ConnectivityStatus.offline);
      _transportLostAt ??= _now();
      return _status;
    }

    // Transport is back and nothing was ever lost.
    if (_transportLostAt == null) {
      _cancelReconnectDeadline();
      // A transport report is NOT proof of internet access, so a still
      // -`unknown` service stays `unknown` here. Claiming `online` from a
      // transport flag is exactly what makes a captive portal look healthy —
      // only [confirmReachable] (a real request succeeding) proves anything.
      if (_status != ConnectivityStatus.unknown) {
        _setStatus(ConnectivityStatus.online);
      }
      return _status;
    }

    // We were offline and the transport returned. Stay in `reconnecting`
    // until a request proves it, but give up and report offline if the
    // transport never actually works.
    final elapsed = _now().difference(_transportLostAt!);
    if (elapsed >= reconnectTimeout) {
      _cancelReconnectDeadline();
      _setStatus(ConnectivityStatus.offline);
      return _status;
    }

    _setStatus(ConnectivityStatus.reconnecting);
    _armReconnectDeadline();
    return _status;
  }

  /// The single place a status actually changes.
  ///
  /// Emits only on a real transition, so a listener is never woken for a value
  /// it already had (which would cause a needless banner rebuild), and every
  /// mutator is guaranteed to be broadcast — the omission this centralises.
  void _setStatus(ConnectivityStatus next) {
    if (_status == next) return;
    _status = next;
    if (!_disposed && !_controller.isClosed) _controller.add(next);
  }

  /// Schedules the automatic expiry of [ConnectivityStatus.reconnecting].
  ///
  /// Re-armed (never stacked) on every call, so a flurry of transport events
  /// cannot leave several pending timers racing to overwrite a state that has
  /// since been resolved.
  void _armReconnectDeadline() {
    _cancelReconnectDeadline();
    if (_disposed) return;
    _reconnectDeadline = Timer(reconnectTimeout, () {
      // Re-check inside the callback: a request may have promoted the state to
      // online after this timer was armed but before it fired, and expiring
      // then would report a working network as offline.
      if (_status != ConnectivityStatus.reconnecting) return;
      _setStatus(ConnectivityStatus.offline);
    });
  }

  void _cancelReconnectDeadline() {
    _reconnectDeadline?.cancel();
    _reconnectDeadline = null;
  }

  void dispose() {
    // Idempotent: a caller may dispose defensively and this also runs from a
    // provider's onDispose, so a double `close()` would throw.
    if (_disposed) return;
    _disposed = true;
    _cancelReconnectDeadline();
    _transportSub?.cancel();
    _transportSub = null;
    _controller.close();
  }
}

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService(Connectivity());
  ref.onDispose(() => service.dispose());
  return service;
});

/// Live connection state.
///
/// Built on a long-lived stream rather than the plugin's event stream, so a
/// connectivity change caused by real traffic (`confirmReachable`,
/// `noteRequestFailure`) reaches the UI just as a platform event would. The
/// plugin's own stream is folded in as an additional trigger so genuine
/// disconnects are still noticed even when no request is in flight — a device
/// that goes into a lift mid-request makes no HTTP call to report it.
final connectivityStatusProvider = StreamProvider<ConnectivityStatus>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  // Opt in to the platform's transport events here rather than in the
  // constructor, so the service stays constructible in tests that have no
  // platform binding.
  service.listenToTransport();
  return service.onStatusChanged.handleError((Object _) {});
});

/// Provider that exposes current connectivity as a boolean (true = online).
///
/// Retained for existing consumers; see [ConnectivityService.isOnline] for
/// why `reconnecting` and `unknown` are both reported as `false`.
final isConnectedProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  return service.onConnectivityChanged.handleError((Object _) {});
});
