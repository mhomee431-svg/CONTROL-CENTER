import 'dart:convert';

import 'package:flutter/services.dart';

/// Instant local India pincode → city/state lookup using the bundled
/// `assets/pincodes.json` dataset (19,238 pincodes, O(1) map access).
///
/// The dataset loads once on first use and ALL lookups happen on-device in
/// milliseconds — no network calls, no backend round-trip.
class PincodeInfo {
  const PincodeInfo(this.pincode, this.city, this.state);
  final String pincode;
  final String city;
  final String state;
}

class PincodeLookup {
  PincodeLookup._();
  static final PincodeLookup instance = PincodeLookup._();

  static const String _assetPath = 'assets/pincodes.json';

  Map<String, PincodeInfo>? _index;
  Future<void>? _loadingFuture;

  /// Loads the bundled dataset into memory (called once, lazily).
  Future<void> ensureLoaded() {
    if (_index != null) return Future.value();
    if (_loadingFuture != null) return _loadingFuture!;
    _loadingFuture = _doLoad().whenComplete(() {
      _loadingFuture = null;
    });
    return _loadingFuture!;
  }

  Future<void> _doLoad() async {
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final map = <String, PincodeInfo>{};
      decoded.forEach((pin, value) {
        final v = value as Map<String, dynamic>;
        map[pin] = PincodeInfo(pin, v['c'] as String? ?? '', v['s'] as String? ?? '');
      });
      _index = map;
    } on Exception catch (_) {
      _index = const {};
    }
  }

  /// Synchronous, in-memory lookup — returns in microseconds.
  /// Returns null when the pincode isn't in the dataset.
  PincodeInfo? lookupSync(String pincode) {
    final clean = pincode.trim();
    if (clean.length != 6 || !RegExp(r'^\d{6}$').hasMatch(clean)) return null;
    return _index?[clean];
  }

  /// Async lookup — waits for the first load, then returns instantly.
  Future<PincodeInfo?> lookup(String pincode) async {
    await ensureLoaded();
    return lookupSync(pincode);
  }

  /// True after the dataset has been loaded at least once.
  bool get isLoaded => _index != null;
}