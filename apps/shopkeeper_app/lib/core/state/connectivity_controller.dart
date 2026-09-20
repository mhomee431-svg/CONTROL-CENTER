import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env_config.dart';
import '../network/connectivity_service.dart';

/// The three connectivity states the UI is allowed to show. `online` renders
/// nothing; the other two render the app-wide banner.
enum ConnectivityStatus { online, offline, reconnecting }

@immutable
class ConnectivityState {
  const ConnectivityState._({required this.status});

  const ConnectivityState.online() : this._(status: ConnectivityStatus.online);
  const ConnectivityState.offline()
      : this._(status: ConnectivityStatus.offline);
  const ConnectivityState.reconnecting()
      : this._(status: ConnectivityStatus.reconnecting);

  final ConnectivityStatus status;

  bool get isOnline => status == ConnectivityStatus.online;
}

/// How reachability of OUR backend is verified. `connectivity_plus` only knows
/// about the *network link* — Wi-Fi can be up while the backend is down — so
/// "Reconnecting" ends only when a real `/health` round-trip succeeds.
typedef BackendProbe = Future<bool> Function();

/// Production probe: a short `GET {apiBaseUrl}/health`, mirroring the pattern
/// `DevBackendDiscovery` already uses at startup.
Future<bool> probeViaHealth() async {
  try {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 3),
      responseType: ResponseType.json,
    ));
    final response =
        await dio.get<Object?>('${EnvConfig.apiBaseUrl}/health');
    return response.statusCode == 200;
  } catch (_) {
    return false;
  }
}

/// Injectable so tests decide when the backend "comes back".
final backendProbeProvider =
    Provider<BackendProbe>((ref) => probeViaHealth);

final connectivityServiceProvider = Provider<ConnectivityService>(
  (ref) => PlusConnectivityService(),
);

final connectivityControllerProvider = NotifierProvider<ConnectivityController,
    ConnectivityState>(ConnectivityController.new);

/// Owns the Online / Offline / Reconnecting state machine.
///
/// Rules:
///  * the OS link dropping → **Offline** immediately (no probing to confirm
///    what the OS already knows);
///  * the link returning → **Reconnecting** until a real backend round-trip
///    succeeds, then **Online** — Wi-Fi alone is not "online" for this app;
///  * a failed probe drops back to **Offline** (the banner's Retry button and
///    the next link change each re-probe — no self-perpetuating timer that
///    would burn battery and complicate tests);
///  * every platform-channel failure degrades silently to **Online** with the
///    banner hidden: the reactive per-request offline errors (already
///    classified by `ApiException`) remain the source of truth then.
class ConnectivityController extends Notifier<ConnectivityState> {
  StreamSubscription<ConnectivitySnapshot>? _subscription;
  int _probeCount = 0;
  bool _firstSyncDone = false;

  @override
  ConnectivityState build() {
    ref.onDispose(() => _subscription?.cancel());
    unawaited(_readCurrentLink());
    try {
      _subscription = ref.read(connectivityServiceProvider).stream().listen(
            _onLinkChanged,
            // A platform-channel hiccup must never crash the app: the banner
            // simply stays where it is and per-request errors still speak.
            onError: (_, _) {},
          );
    } catch (_) {
      // Plugin unavailable (widget tests): stay Online, banner hidden.
    }
    return const ConnectivityState.online();
  }

  /// Times the backend probe was attempted — asserted in tests.
  @visibleForTesting
  int get probeCount => _probeCount;

  Future<void> _readCurrentLink() async {
    try {
      final snapshot = await ref.read(connectivityServiceProvider).current();
      await _onLinkChanged(snapshot);
    } catch (_) {
      // See build(): degrade to Online, banner hidden.
    }
  }

  Future<void> _onLinkChanged(ConnectivitySnapshot snapshot) async {
    final isFirstSync = !_firstSyncDone;
    _firstSyncDone = true;
    switch (snapshot.link) {
      case TransportLink.disconnected:
        if (state.status != ConnectivityStatus.offline) {
          state = const ConnectivityState.offline();
        }
      case TransportLink.connected:
        // The FIRST sync must verify the backend even if the (optimistic)
        // build state already says Online; afterwards, duplicate "connected"
        // events while Online are noise and must not re-probe.
        if (isFirstSync || state.status != ConnectivityStatus.online) {
          await _probeAndSet();
        }
      case TransportLink.unknown:
        break;
    }
  }

  /// Link is up — verify the BACKEND answers before claiming Online.
  Future<void> _probeAndSet() async {
    if (state.status != ConnectivityStatus.reconnecting) {
      state = const ConnectivityState.reconnecting();
    }
    final reachable = await _probe();
    if (!ref.mounted) return;
    state = reachable
        ? const ConnectivityState.online()
        : const ConnectivityState.offline();
  }

  Future<bool> _probe() {
    _probeCount++;
    return ref.read(backendProbeProvider)();
  }

  /// Manual re-probe (the offline banner's Retry button).
  Future<void> retryNow() async {
    if (state.status == ConnectivityStatus.online) return;
    await _probeAndSet();
  }
}
