import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Monitors network connectivity status and exposes a stream of connection states.
class ConnectivityService {
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isConnected = true;

  ConnectivityService(this._connectivity);

  bool get isConnected => _isConnected;

  /// Stream that emits true when connected, false when disconnected.
  Stream<bool> get onConnectivityChanged {
    return _connectivity.onConnectivityChanged.map((results) {
      final connected = results.any((r) => r != ConnectivityResult.none);
      _isConnected = connected;
      return connected;
    });
  }

  Future<bool> checkConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    _isConnected = results.any((r) => r != ConnectivityResult.none);
    return _isConnected;
  }

  void dispose() {
    _subscription?.cancel();
  }
}

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService(Connectivity());
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider that exposes current connectivity status (true = connected).
///
/// Platform errors (e.g. the plugin being unavailable in widget tests) are
/// swallowed: consumers fall back to "connected" instead of surfacing an
/// error state.
final isConnectedProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  return service.onConnectivityChanged.handleError((Object _) {});
});
