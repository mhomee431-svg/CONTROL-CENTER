import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/router/app_router.dart';
import 'package:hyperlocal_shopkeeper_app/core/router/route_names.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/shop_models.dart';

CategoryCapabilitySet gatesFor(String category, [String? businessType]) =>
    resolveCategoryCapabilities(category, businessType);

void main() {
  // A hidden button still leaves the destination reachable by deep link, so the
  // guard is what actually stops a service business reaching an inventory
  // ledger. These tests assert the refusal, not the hiding.
  group('capability-gated routes', () {
    test('a stocked shop may reach import and products', () {
      final gates = gatesFor('HARDWARE');
      expect(capabilityDeniedRoute(gates, Routes.inventoryImport), isNull);
      expect(capabilityDeniedRoute(gates, Routes.products), isNull);
    });

    test('a restaurant is refused inventory import', () {
      expect(
        capabilityDeniedRoute(gatesFor('RESTAURANTS'), Routes.inventoryImport),
        Routes.dashboard,
      );
    });

    test('a restaurant is refused the product catalogue', () {
      expect(
        capabilityDeniedRoute(gatesFor('RESTAURANTS'), Routes.products),
        Routes.dashboard,
      );
    });

    test('every service category is refused both', () {
      for (final code in [
        'RESTAURANTS',
        'TRANSPORT',
        'PERSONAL_TRANSPORT_TRAVEL',
      ]) {
        final gates = gatesFor(code);
        expect(capabilityDeniedRoute(gates, Routes.inventoryImport),
            Routes.dashboard, reason: code);
        expect(capabilityDeniedRoute(gates, Routes.products), Routes.dashboard,
            reason: code);
      }
    });

    test('a service-typed shop loses import even if its category is stocked', () {
      // The business type is the second axis: the same hardware shop, trading
      // as a service, keeps no stock.
      final retail = gatesFor('HOUSEHOLD_GOODS', 'Retail');
      final service = gatesFor('HOUSEHOLD_GOODS', 'Service');
      expect(capabilityDeniedRoute(retail, Routes.inventoryImport), isNull);
      expect(capabilityDeniedRoute(service, Routes.inventoryImport),
          Routes.dashboard);
    });

    test('a deeper sub-path of a denied route is refused too', () {
      // Deep links are exactly how a guarded screen gets reached in
      // production, so a prefix match on the bare route would be no guard at all.
      final gates = gatesFor('TRANSPORT');
      expect(
        capabilityDeniedRoute(gates, '${Routes.inventoryImport}/history'),
        Routes.dashboard,
      );
    });

    test('routes needing no capability are never refused', () {
      final gates = gatesFor('RESTAURANTS');
      for (final route in [
        Routes.dashboard,
        Routes.shops,
        Routes.shopSettings,
      ]) {
        expect(capabilityDeniedRoute(gates, route), isNull, reason: route);
      }
    });

    test('an unclassified shop is let through, not locked out', () {
      // Regression: refusing here broke real navigation. With no category every
      // gate reads false, so a shopkeeper whose summary had not loaded yet was
      // bounced off their own products screen. The backend still validates on
      // write, so failing open is the safe side to land on.
      final gates = gatesFor('NOT_A_CATEGORY');
      expect(capabilityDeniedRoute(gates, Routes.inventoryImport), isNull);
      expect(capabilityDeniedRoute(gates, Routes.products), isNull);
    });

    test('an empty capability set gates nothing', () {
      const empty = CategoryCapabilitySet(categoryCode: '');
      expect(capabilityDeniedRoute(empty, Routes.inventoryImport), isNull);
      expect(capabilityDeniedRoute(empty, Routes.products), isNull);
    });

    test('an unknown category is not treated as a service category', () {
      // Regression that mattered: the resolver always appends CONTACT and
      // LOCATION, so an empty capability set is NOT the signal for "unknown" —
      // otherwise every shop carrying an unrecognised code was silently denied
      // products and import.
      final unknown = gatesFor('GROCERY');
      expect(unknown.capabilities, isNotEmpty);
      expect(capabilityDeniedRoute(unknown, Routes.products), isNull);
      expect(capabilityDeniedRoute(unknown, Routes.inventoryImport), isNull);
    });

    test('a real service category is still refused, empty set or not', () {
      // The fail-open must not become a blanket bypass: a resolved RESTAURANTS
      // set is non-empty, so the guard applies exactly as before.
      final gates = gatesFor('RESTAURANTS');
      expect(gates.isEmpty, isFalse);
      expect(capabilityDeniedRoute(gates, Routes.inventoryImport),
          Routes.dashboard);
    });
  });
}