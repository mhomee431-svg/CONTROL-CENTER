import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/location/discovery_radius.dart';

/// The discovery radius for the home feed's `nearby_shops`.
///
/// The backend default (`GET /home/feed`, 10 km) rules the first load, so the
/// state starts at null — NOT at a number the UI invented. A customer who taps
/// the widen action in the empty state steps the radius up one notch at a time
/// (10 → 25 → 50 → 100 km, the server's max); each step is a REAL backend
/// query with a wider `radius_km`, never a client-side filter over the
/// already-empty list.
///
/// No explicit invalidate anywhere: `homeControllerProvider` watches this, so
/// a new radius re-reads the feed in the same frame. Widening is one-way within
/// a session — narrowing an already-empty result is how a customer stays empty.
final homeSearchRadiusProvider =
    NotifierProvider<HomeSearchRadiusController, double?>(
      HomeSearchRadiusController.new,
    );

class HomeSearchRadiusController extends Notifier<double?> {
  @override
  double? build() => null;

  /// Steps to the next notch. A no-op at the ceiling: the backend rejects
  /// anything above 100 km, so asking anyway would be a button that does
  /// nothing but fail. The feed re-read is not triggered here on purpose —
  /// `homeControllerProvider` watches this provider, so a new value produces a
  /// new request in the same frame and there is no path where one happens
  /// without the other.
  void widen() {
    final next = nextDiscoveryRadius(state);
    if (next == null) return;
    state = next;
  }
}
