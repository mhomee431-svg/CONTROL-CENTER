import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/location/discovery_radius.dart';

void main() {
  group('the discovery radius ladder', () {
    test('the first offered step is wider than the backend default', () {
      // `radius_km` defaults to 10 km server-side, so the empty state was
      // already showing the result of a 10 km query. Offering "Search within
      // 10 km" as the recovery re-issued that exact same query and came back
      // empty again — a button that looked live and changed nothing.
      expect(nextDiscoveryRadius(null), greaterThan(kBackendDefaultDiscoveryRadiusKm));
      expect(nextDiscoveryRadius(null), 25);
      expect(canWidenDiscoveryRadius(null), isTrue);
      expect(nextDiscoveryRadiusLabel(null), 'Search within 25 km');
    });

    test('steps up one notch at a time and never goes back down', () {
      // Narrowing an already-empty result is how a customer stays empty, so the
      // ladder is strictly increasing from wherever it starts.
      expect(nextDiscoveryRadius(10), 25);
      expect(nextDiscoveryRadius(25), 50);
      expect(nextDiscoveryRadius(50), 100);
    });

    test('stops at the backend maximum instead of asking for more', () {
      // `radius_km` is `le=100` server-side. A step beyond that is a request the
      // server rejects with a 422 — so the value never reaches it and the
      // button that would offer it is never rendered.
      expect(nextDiscoveryRadius(100), isNull);
      expect(canWidenDiscoveryRadius(100), isFalse);
      expect(kDiscoveryRadiusSteps.last, 100);
      expect(nextDiscoveryRadiusLabel(100), 'Searching up to 100 km');
    });

    test('the label states the radius the customer is about to ask for', () {
      // A bare "search wider" says nothing about what is leaving the device.
      expect(nextDiscoveryRadiusLabel(null), 'Search within 25 km');
      expect(nextDiscoveryRadiusLabel(10), 'Search within 25 km');
      expect(nextDiscoveryRadiusLabel(25), 'Search within 50 km');
      expect(nextDiscoveryRadiusLabel(50), 'Search within 100 km');
    });

    test('every step is inside what the backend accepts', () {
      for (final step in kDiscoveryRadiusSteps) {
        expect(step, greaterThan(0), reason: 'radius must be positive');
        expect(step, lessThanOrEqualTo(100), reason: 'backend rejects >100');
      }
      expect(
        kDiscoveryRadiusSteps.toSet().length,
        kDiscoveryRadiusSteps.length,
        reason: 'a repeated step would strand the customer on one notch',
      );
    });
  });
}
