import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// How the device's transport looks right now — the raw platform view before
/// any backend probing.
enum TransportLink { connected, disconnected, unknown }

/// One connectivity reading: what the OS says about the network link.
@immutable
class ConnectivitySnapshot {
  const ConnectivitySnapshot({required this.link});

  final TransportLink link;

  static const unknown = ConnectivitySnapshot(link: TransportLink.unknown);
}

/// Source of connectivity truth, abstracted so tests can feed a fake stream
/// instead of the platform channel (the app never talks to the plugin
/// directly).
abstract interface class ConnectivityService {
  /// The reading at this instant.
  Future<ConnectivitySnapshot> current();

  /// Every subsequent change while subscribed.
  Stream<ConnectivitySnapshot> stream();
}

/// Production implementation over `connectivity_plus`.
class PlusConnectivityService implements ConnectivityService {
  PlusConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  /// Any active transport other than `none` means the device has a link.
  /// Matching on emptiness (not on every enum constant) keeps this working
  /// when connectivity_plus adds new transports (it already grew `satellite`).
  static TransportLink _map(List<ConnectivityResult> results) =>
      results.isEmpty || results.contains(ConnectivityResult.none)
          ? TransportLink.disconnected
          : TransportLink.connected;

  @override
  Future<ConnectivitySnapshot> current() async =>
      ConnectivitySnapshot(link: _map(await _connectivity.checkConnectivity()));

  @override
  Stream<ConnectivitySnapshot> stream() => _connectivity.onConnectivityChanged
      .map((results) => ConnectivitySnapshot(link: _map(results)));
}
