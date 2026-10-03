import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/location/discovery_radius.dart';

void main() {
  group('the discovery radius ladder', () {
    test('starts unset so the backend default rules the first load', () {
      // Nothing the UI invents should override the server's own default on a
      // cold load — the customer has not asked for anything yet.
      expect(nextDiscoveryRadius(null), 10);
      expect(canWidenDiscoveryRadius(null), isTrue);
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
      expect(nextDiscoveryRadiusLabel(null), 'Search within 10 km');
      expect(nextDiscoveryRadiusLabel(10), 'Search within 25 km');
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
