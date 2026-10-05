/// CAPABILITY-DRIVEN FORM — the fields change with the category, the look does
/// not.
///
/// The principle under test is that a shopkeeper is never shown one giant form:
/// the SET of inputs is decided by the backend's capabilities, while every input
/// still looks like every other input in the app. These pin the first half; the
/// visual half is pinned by `capability_fields_view_test.dart`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/capability_fields.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/shop_models.dart';

Set<String> _keysOf(CategoryCapabilitySet set) =>
    capabilityFieldsFor(set).map((f) => f.key).toSet();

void main() {
  group('fields follow the capability set', () {
    test('a restaurant is not asked for stock-shaped shop inputs', () {
      final set = resolveCategoryCapabilities('RESTAURANTS', 'Retail');
      final keys = _keysOf(set);

      // What a restaurant DOES get, because it serves and takes bookings.
      expect(keys, contains('service_summary'));
      expect(keys, contains('booking_lead_hours'));

      // What it must never be asked: the backend does not grant INVENTORY, so
      // showing a stock-shaped input would be the app inventing a rule.
      expect(set.has(CategoryCapability.inventory), isFalse);
      expect(set.has(CategoryCapability.barcode), isFalse);
    });

    test('a pharmacy IS asked for the document it must hold', () {
      final set = resolveCategoryCapabilities('PHARMACY_HEALTHCARE', 'Retail');
      expect(_keysOf(set), contains('gst_number'));
      expect(set.has(CategoryCapability.documents), isTrue);
    });

    test('business type narrows the form, not just the feature list', () {
      final retail = resolveCategoryCapabilities('HOUSEHOLD_GOODS', 'Retail');
      final service = resolveCategoryCapabilities('HOUSEHOLD_GOODS', 'Service');

      // A Service business trades without stock, so the stock-shaped fields it
      // would have been shown must disappear rather than linger disabled.
      expect(service.capabilities.length,
          lessThan(retail.capabilities.length));
      expect(service.isEmpty, isFalse);
    });

    test('an unknown category shows only the universal fields, not a full form', () {
      // The safe failure. Inventing a full form for a category this build does
      // not recognise is how a shopkeeper submits data the server rejects.
      //
      // It is NOT empty: CONTACT and LOCATION are granted to every business by
      // the backend's `_ALWAYS`, so a contact field is correct. What must not
      // happen is every category-specific input appearing at once.
      final set = resolveCategoryCapabilities('NOT_A_CATEGORY', null);
      final keys = _keysOf(set);

      expect(keys, isNotEmpty, reason: 'every business must give a contact');
      for (final key in keys) {
        expect(key, anyOf('contact_phone'),
            reason: '$key must not be offered for an unknown category');
      }
    });

    test('field order is stable across calls', () {
      final set = resolveCategoryCapabilities('RESTAURANTS', 'Retail');
      expect(
        capabilityFieldsFor(set).map((f) => f.key).toList(),
        capabilityFieldsFor(set).map((f) => f.key).toList(),
      );
    });

    test('every capability without a spec contributes nothing', () {
      // Capabilities that govern other screens (products, offers, POS, import)
      // must not invent an input on the shop-level form.
      for (final capability in CategoryCapability.values) {
        final set =
            CategoryCapabilitySet(categoryCode: 'X', capabilities: {capability});
        for (final field in capabilityFieldsFor(set)) {
          expect(kCapabilityFields[capability], contains(field),
              reason: '${field.key} is not registered to $capability');
        }
      }
    });

    test('field keys are unique', () {
      final set = resolveCategoryCapabilities('RESTAURANTS', 'Retail');
      expect(_keysOf(set).length, capabilityFieldsFor(set).length,
          reason: 'a duplicate key would make one field overwrite another');
    });
  });

  group('validation', () {
    test('a required field blocks submission when blank', () {
      final set = resolveCategoryCapabilities('RESTAURANTS', 'Retail');
      expect(isCapabilityFormComplete(set, const {}), isFalse);
      expect(validateCapabilityFields(set, const {})['opening_time'], isNotNull);
    });

    test('optional fields do not block an otherwise complete form', () {
      final set = resolveCategoryCapabilities('RESTAURANTS', 'Retail');
      // service_summary and business_highlights are optional.
      expect(
        isCapabilityFormComplete(set, const {
          'opening_time': '09:00',
          'closing_time': '21:00',
          'contact_phone': '9876543210',
        }),
        isTrue,
      );
    });

    test('an invalid value is reported against its own key', () {
      final set = resolveCategoryCapabilities('PHARMACY_HEALTHCARE', 'Retail');
      expect(
        validateCapabilityFields(set, const {'gst_number': 'not-a-gst'})
            .containsKey('gst_number'),
        isTrue,
      );
      expect(
        validateCapabilityFields(set, const {'gst_number': '22AAAAA0000A1Z5'})
            .containsKey('gst_number'),
        isFalse,
        reason: 'a well-formed GST number must pass the shape check',
      );
    });

    test('a negative or non-numeric number is rejected', () {
      final set = resolveCategoryCapabilities('RESTAURANTS', 'Retail');
      for (final bad in ['-3', 'soon']) {
        expect(
          validateCapabilityFields(set, {'booking_lead_hours': bad})
              .containsKey('booking_lead_hours'),
          isTrue,
          reason: '"$bad" must be rejected',
        );
      }
      expect(
        validateCapabilityFields(set, const {'booking_lead_hours': '48'})
            .containsKey('booking_lead_hours'),
        isFalse,
      );
    });

    test('a too-short phone is rejected', () {
      final set = resolveCategoryCapabilities('RESTAURANTS', 'Retail');
      expect(
        validateCapabilityFields(set, const {'contact_phone': '12345'})
            .containsKey('contact_phone'),
        isTrue,
      );
      expect(
        validateCapabilityFields(set, const {'contact_phone': '+91 98765 43210'})
            .containsKey('contact_phone'),
        isFalse,
      );
    });
  });

  group('submission', () {
    test('only granted, non-blank fields are submitted', () {
      // HOUSEHOLD_GOODS, not RESTAURANTS: a restaurant legitimately holds
      // DOCUMENTS, so gst_number would be a real field there and the
      // stale-state case could not be observed.
      final set = resolveCategoryCapabilities('HOUSEHOLD_GOODS', 'Retail');
      expect(set.has(CategoryCapability.documents), isFalse);

      final submitted = submittedCapabilityFields(set, const {
        'opening_time': ' 09:00 ',
        'contact_phone': '9876543210',
        // Present in the values map but NOT in this form: stale form state must
        // not smuggle it to the backend.
        'gst_number': '22AAAAA0000A1Z5',
      });

      expect(submitted['opening_time'], '09:00', reason: 'values are trimmed');
      expect(submitted.containsKey('gst_number'), isFalse,
          reason: 'a field outside this capability set must never be sent');
    });

    test('a service business never submits a stock-shaped field', () {
      final set = resolveCategoryCapabilities('HOUSEHOLD_GOODS', 'Service');
      final submitted = submittedCapabilityFields(set, const {
        'booking_lead_hours': '',
        'opening_time': '10:00',
        'contact_phone': '9876543210',
      });
      expect(submitted.keys, isNot(contains('booking_lead_hours')));
    });
  });

  group('personal transport / personal travel', () {
    // The spec lists these business fields explicitly, and a travel provider is
    // a service business: no catalogue, no stock.
    test('renders service area and travel details', () {
      final set = const CategoryCapabilitySet(
        categoryCode: 'PERSONAL_TRANSPORT_TRAVEL',
        capabilities: <CategoryCapability>{
          CategoryCapability.categorySpecificData,
          CategoryCapability.services,
          CategoryCapability.operatingHours,
        },
      );
      final keys = capabilityFieldsFor(set).map((f) => f.key).toList();
      expect(keys, contains('service_area'));
      expect(keys, contains('service_types'));
      expect(keys, contains('travel_details'));
      // Business-level fields from the other capabilities still come through.
      expect(keys, contains('service_summary'));
      expect(keys, contains('opening_time'));
    });

    test('keeps the generic highlights field as well', () {
      final set = const CategoryCapabilitySet(
        categoryCode: 'PERSONAL_TRANSPORT_TRAVEL',
        capabilities: <CategoryCapability>{
          CategoryCapability.categorySpecificData,
        },
      );
      final keys = capabilityFieldsFor(set).map((f) => f.key).toList();
      expect(keys, contains('business_highlights'));
      expect(keys, contains('service_area'));
    });

    test('never shows a product or stock field', () {
      final set = const CategoryCapabilitySet(
        categoryCode: 'PERSONAL_TRANSPORT_TRAVEL',
        capabilities: <CategoryCapability>{
          CategoryCapability.categorySpecificData,
          CategoryCapability.services,
          CategoryCapability.booking,
        },
      );
      final keys = capabilityFieldsFor(set).map((f) => f.key).toSet();
      expect(keys, isNot(contains('barcode')));
      expect(keys, isNot(contains('quantity')));
      expect(keys, isNot(contains('sku')));
    });

    test('without the capability, no trade-specific field appears', () {
      // The backend did not grant CATEGORY_SPECIFIC_DATA, so the form must not
      // invent one even though this category has entries in the map.
      final set = const CategoryCapabilitySet(
        categoryCode: 'PERSONAL_TRANSPORT_TRAVEL',
        capabilities: <CategoryCapability>{CategoryCapability.services},
      );
      final keys = capabilityFieldsFor(set).map((f) => f.key).toList();
      expect(keys, isNot(contains('service_area')));
      expect(keys, isNot(contains('travel_details')));
    });

    test('another category does not inherit travel fields', () {
      final set = const CategoryCapabilitySet(
        categoryCode: 'HARDWARE',
        capabilities: <CategoryCapability>{
          CategoryCapability.categorySpecificData,
        },
      );
      final keys = capabilityFieldsFor(set).map((f) => f.key).toList();
      expect(keys, contains('business_highlights'));
      expect(keys, isNot(contains('service_area')));
      expect(keys, isNot(contains('route_fares')));
      expect(keys, isNot(contains('menu_offerings')));
    });

    test('transport and travel do not share identical fields', () {
      List<CapabilityFieldSpec> fieldsFor(String code) => capabilityFieldsFor(
            CategoryCapabilitySet(
              categoryCode: code,
              capabilities: <CategoryCapability>{
                CategoryCapability.categorySpecificData,
              },
            ),
          );
      final travel = fieldsFor('PERSONAL_TRANSPORT_TRAVEL').map((f) => f.key);
      final transport = fieldsFor('TRANSPORT').map((f) => f.key);
      expect(travel, isNot(equals(transport)));
      expect(transport, contains('route_fares'));
      expect(travel, isNot(contains('route_fares')));
    });

    test('restaurants offer offerings, not a stock form', () {
      final set = const CategoryCapabilitySet(
        categoryCode: 'RESTAURANTS',
        capabilities: <CategoryCapability>{
          CategoryCapability.categorySpecificData,
        },
      );
      expect(capabilityFieldsFor(set).map((f) => f.key),
          contains('menu_offerings'));
    });

    test('service area is optional, not a forced requirement', () {
      // "where supported" in the spec — it must not block submission.
      final set = const CategoryCapabilitySet(
        categoryCode: 'PERSONAL_TRANSPORT_TRAVEL',
        capabilities: <CategoryCapability>{
          CategoryCapability.categorySpecificData,
        },
      );
      expect(isCapabilityFormComplete(set, const {}), isTrue);
    });

    test('category code matching is case-insensitive', () {
      final set = CategoryCapabilitySet(
        categoryCode: 'personal_transport_travel',
        capabilities: <CategoryCapability>{
          CategoryCapability.categorySpecificData,
        },
      );
      expect(capabilityFieldsFor(set).map((f) => f.key),
          contains('service_area'));
    });
  });

  group('kCategorySpecificFields table', () {
    test('every service profile has at least one field', () {
      for (final profile in ServiceCategoryProfile.values) {
        expect(
          kCategorySpecificFields[profile],
          isNotEmpty,
          reason: '$profile would grant the capability but render nothing',
        );
      }
    });

    test('field keys are unique within each category', () {
      // Repeats ACROSS categories are intended — travel and transport share
      // `service_area` because it is the same concept with the same key. What
      // must never happen is one category rendering two inputs on one key.
      for (final entry in kCategorySpecificFields.entries) {
        final keys = entry.value.map((f) => f.key).toList();
        expect(keys.length, keys.toSet().length, reason: '${entry.key}');
      }
    });

    test('sharing a key across categories keeps one consistent label', () {
      // The same key must not mean two different things.
      final byKey = <String, Set<String>>{};
      for (final entry in kCategorySpecificFields.entries) {
        for (final field in entry.value) {
          byKey.putIfAbsent(field.key, () => <String>{}).add(field.label);
        }
      }
      byKey.forEach((key, labels) {
        expect(labels.length, 1, reason: '$key has labels $labels');
      });
    });

    test('every listed field has an icon and a label', () {
      for (final entry in kCategorySpecificFields.entries) {
        for (final field in entry.value) {
          expect(field.icon, isNotEmpty, reason: '${entry.key}.${field.key}');
          expect(field.label, isNotEmpty, reason: '${entry.key}.${field.key}');
        }
      }
    });

    test('no listed field collides with a generic capability field', () {
      // A collision would render two inputs on the same key.
      final generic = kCapabilityFields.values
          .expand((list) => list)
          .map((f) => f.key)
          .toSet();
      final specific =
          kCategorySpecificFields.values.expand((l) => l).map((f) => f.key);
      expect(specific.toSet().intersection(generic), isEmpty);
    });
  });

  group('feature gating', () {
    // The capability set decides not just which FIELDS render, but which
    // features are reachable at all. These are the questions the router and
    // navigation ask.
    test('every service category is blocked from inventory features', () {
      for (final code in [
        'RESTAURANTS',
        'TRANSPORT',
        'PERSONAL_TRANSPORT_TRAVEL',
      ]) {
        final gates = resolveCategoryCapabilities(code, null);
        expect(gates.mayManageProducts, isFalse, reason: code);
        expect(gates.mayManageInventory, isFalse, reason: code);
        expect(gates.mayScanBarcodes, isFalse, reason: code);
        expect(gates.mayImportInventory, isFalse, reason: code);
        // …but a restaurant still publishes offers and keeps hours.
        expect(gates.mayRunOffers, isTrue, reason: code);
        expect(gates.maySetOpeningHours, isTrue, reason: code);
      }
    });

    test('service narrowing closes the inventory doors', () {
      final retail =
          resolveCategoryCapabilities('HOUSEHOLD_GOODS', 'Retail');
      final service =
          resolveCategoryCapabilities('HOUSEHOLD_GOODS', 'Service');
      expect(retail.mayManageInventory, isTrue);
      expect(service.mayManageInventory, isFalse);
      expect(service.mayScanBarcodes, isFalse);
      expect(service.mayImportInventory, isFalse);
      // Narrowing must not take away being contactable.
      expect(service.maySetOpeningHours, isTrue);
    });

    test('a till follows the POS capability, not how shop-like the trade looks', () {
      // A restaurant is granted POS without a product catalogue; furniture is a
      // stocked shop without POS. Both answers must come from the capability
      // alone, never from intuition about the trade.
      expect(resolveCategoryCapabilities('RESTAURANTS', null).mayUsePos,
          isTrue);
      expect(resolveCategoryCapabilities('FURNITURE_HOME_CARE', null).mayUsePos,
          isFalse);
      expect(resolveCategoryCapabilities('TRANSPORT', null).mayUsePos, isFalse);
    });

    test('offers do not require a product catalogue', () {
      // Regression: gating offers on PRODUCT_CATALOG would have stopped a
      // restaurant publishing daily specials, which the backend explicitly
      // allows it to do.
      expect(resolveCategoryCapabilities('RESTAURANTS', null).mayRunOffers,
          isTrue);
      expect(resolveCategoryCapabilities('RESTAURANTS', null).mayManageProducts,
          isFalse);
    });

    test('scanning needs somewhere for the scan to land', () {
      expect(resolveCategoryCapabilities('HARDWARE', null).mayScanBarcodes,
          isTrue);
      expect(resolveCategoryCapabilities('RESTAURANTS', null).mayScanBarcodes,
          isFalse);
    });

    test('an unknown category is blocked from everything', () {
      final gates = resolveCategoryCapabilities('NOT_A_CATEGORY', null);
      expect(gates.featureGates.values.any((granted) => granted), isFalse);
    });
  });
}