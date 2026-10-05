import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/catalog/approved_categories.dart';
import 'package:hyperlocal_app/core/catalog/business_capability.dart';

/// The category-capability model (Master Spec §86-§89) on the client side.
///
/// The backend resolves capabilities and ships them on the shop payload; these
/// tests pin what the app does with that list, and — just as importantly — what
/// it does when the list is missing.
void main() {
  group('wire parsing', () {
    test('every backend capability name is understood', () {
      // Mirrors CustomerCapability in app.models.merchant_category. A rename on
      // either side that the other does not know fails here, not silently in
      // production where a restaurant would fall back to a product grid.
      const backendNames = [
        'product_catalog',
        'menu',
        'service_profile',
        'availability',
        'quote_request',
        'contact',
        'directions',
        'ratings',
        'offers',
      ];

      for (final name in backendNames) {
        expect(
          BusinessCapability.tryParse(name),
          isNotNull,
          reason: 'the backend sends "$name", which this build cannot read',
        );
      }
      expect(backendNames.length, BusinessCapability.values.length);
    });

    test('an unknown capability is ignored, not fatal', () {
      final set = BusinessCapabilitySet.fromWire(['menu', 'live_streaming']);
      expect(set.has(BusinessCapability.menu), isTrue);
      expect(set.isNotEmpty, isTrue);
    });

    test('a non-list payload yields the empty set instead of throwing', () {
      expect(BusinessCapabilitySet.fromWire('menu').isEmpty, isTrue);
      expect(BusinessCapabilitySet.fromWire(null).isEmpty, isTrue);
      expect(BusinessCapabilitySet.fromWire(42).isEmpty, isTrue);
    });

    test('case and padding are tolerated', () {
      final set = BusinessCapabilitySet.fromWire(['  MENU  ']);
      expect(set.has(BusinessCapability.menu), isTrue);
    });
  });

  group('resolution order', () {
    test('a non-empty wire list always wins', () {
      final set = BusinessCapabilitySet.resolve(
        wire: ['menu'],
        categoryName: 'Hardware',
        businessType: 'Retail',
      );
      expect(set.supportsMenu, isTrue);
      expect(set.supportsProductCatalog, isFalse);
    });

    test('business type "Service" means a service profile', () {
      final set = BusinessCapabilitySet.resolve(businessType: ' service ');
      expect(set.supportsServiceProfile, isTrue);
      expect(set.supportsProductCatalog, isFalse);
      // No provider record behind a generic service shop, so no booking promise.
      expect(set.supportsQuoteRequest, isFalse);
    });

    test('a known category name falls back to the compiled table', () {
      expect(
        BusinessCapabilitySet.resolve(categoryName: 'Restaurants').supportsMenu,
        isTrue,
      );
      expect(
        BusinessCapabilitySet.resolve(categoryName: 'Transport')
            .supportsQuoteRequest,
        isTrue,
      );
      expect(
        BusinessCapabilitySet.resolve(categoryName: 'Hardware')
            .supportsProductCatalog,
        isTrue,
      );
    });

    test('an unknown category keeps the product default, not nothing', () {
      // A physical shop is the common case, and blanking its profile would be
      // worse than showing an inventory surface.
      final set = BusinessCapabilitySet.resolve(
        categoryName: 'Some New Category',
      );
      expect(set.supportsProductCatalog, isTrue);
      expect(set.isNotEmpty, isTrue);
    });
  });

  group('the policy itself (Master Spec §86-§89)', () {
    test('a restaurant never gets a product catalog', () {
      for (final category in ApprovedCategories.all.where(
        (c) => c.type == ApprovedCategoryType.restaurant,
      )) {
        final set = businessCapabilitiesForCategoryName(category.name);
        expect(
          set.supportsProductCatalog,
          isFalse,
          reason: '${category.name} must not inherit price/stock UI',
        );
        expect(set.supportsMenu, isTrue);
        // Rule 4: discovery, not delivery.
        expect(category.supportsDelivery, isFalse);
      }
    });

    test('a service category gets a profile and no price/stock UI', () {
      for (final category in ApprovedCategories.all.where(
        (c) => c.type == ApprovedCategoryType.service,
      )) {
        final set = businessCapabilitiesForCategoryName(category.name);
        expect(
          set.supportsServiceProfile,
          isTrue,
          reason: '${category.name} is a service domain',
        );
        expect(set.supportsProductCatalog, isFalse);
        expect(
          set.supportsQuoteRequest,
          isTrue,
          reason:
              '${category.name} has a real quote contract, so the request '
              'entry point is honest',
        );
      }
    });

    test('a product category keeps price, stock, distance and contact', () {
      for (final category in ApprovedCategories.all.where(
        (c) => c.type == ApprovedCategoryType.product,
      )) {
        final set = businessCapabilitiesForCategoryName(category.name);
        expect(set.supportsProductCatalog, isTrue, reason: category.name);
        expect(set.supportsContact, isTrue, reason: category.name);
        expect(set.supportsDirections, isTrue, reason: category.name);
        expect(set.needsBusinessProfile, isFalse, reason: category.name);
      }
    });

    test('every compiled category resolves to a non-empty capability set', () {
      for (final category in ApprovedCategories.all) {
        expect(
          businessCapabilitiesForCategoryName(category.name).isNotEmpty,
          isTrue,
          reason: category.name,
        );
      }
    });

    test('grocery is still not a product-discovery category', () {
      // The deny-list that keeps grocery out of the platform is unchanged.
      expect(
        ApprovedCategories.isProductBrowsable('grocery & general food'),
        isFalse,
      );
      expect(ApprovedCategories.isProductBrowsable('restaurants'), isFalse);
      expect(
        ApprovedCategories.isProductBrowsable('a brand new category'),
        isTrue,
      );
    });
  });

  group('value semantics', () {
    test('two sets with the same members are equal', () {
      final a = BusinessCapabilitySet.fromWire(['menu', 'contact']);
      final b = BusinessCapabilitySet.fromWire(['contact', 'menu', 'menu']);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('capability questions read the resolved set', () {
      final set = BusinessCapabilitySet.fromWire([
        'service_profile',
        'quote_request',
      ]);
      expect(set.supportsServiceProfile, isTrue);
      expect(set.supportsQuoteRequest, isTrue);
      expect(set.supportsMenu, isFalse);
      expect(set.needsBusinessProfile, isTrue);
    });
  });
}
