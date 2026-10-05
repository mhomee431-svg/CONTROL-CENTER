import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/shop_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/shop_registration/domain/shop_registration_state.dart'
    as wizard;

/// The five business types, pinned from every angle they can drift from.
///
/// These types are the second axis of the whole capability model: "Service"
/// removes the stock capabilities, everything else keeps them. A type string that
/// no longer matches the backend's is not a cosmetic problem — it silently means
/// "unknown type, stay permissive", which is how a Service shop ends up shown a
/// stock ledger. So the vocabulary is checked in the places that can break it.
void main() {
  const expected = <String>[
    'Retail',
    'Wholesale',
    'Retail + Wholesale',
    'Service',
    'Other',
  ];

  group('the vocabulary itself', () {
    test('is exactly the five types the backend defines', () {
      expect(kBusinessTypes, expected);
    });

    test('has no duplicates', () {
      expect(kBusinessTypes.toSet().length, kBusinessTypes.length);
    });

    test('spells the combined type the way the backend does', () {
      // The defect this file exists for: the registration wizard offered
      // `Retail & Wholesale`, which is a DIFFERENT string. The backend matches
      // narrowing rules on exact text, so that value matched nothing.
      expect(kBusinessTypes, contains('Retail + Wholesale'));
      expect(kBusinessTypes, isNot(contains('Retail & Wholesale')));
    });
  });

  group('every consumer shares one list', () {
    test('the capability contract vocabulary is the same list', () {
      expect(kBusinessTypesServerVocabulary, kBusinessTypes);
    });

    test('the registration wizard offers the same list', () {
      // The wizard is the screen that actually submits the value, so it is the
      // one that matters most. It used to carry a private list whose combined
      // entry was spelled `Retail & Wholesale`.
      expect(wizard.kBusinessTypes, expected);
      expect(wizard.kBusinessTypes, kBusinessTypes);
    });

    test('the registration wizard exposes no second vocabulary', () {
      // An `identical()` check on two const lists was tried here and does NOT
      // work — Dart is free to canonicalise them, so it passed against a wizard
      // that had been given its own copy with a typo. Comparing the VALUES is
      // what actually catches it.
      expect(List.of(wizard.kBusinessTypesCanonical), expected);
    });
  });

  group('narrowing depends on an exact match', () {
    test('Service is the only type that removes the stock capabilities', () {
      final stockShaped = <CategoryCapability>{
        CategoryCapability.productCatalog,
        CategoryCapability.inventory,
        CategoryCapability.barcode,
        // `import_` because `import` is a Dart keyword.
        CategoryCapability.import_,
        CategoryCapability.pos,
      };
      final service = resolveCategoryCapabilities('HARDWARE', 'Service');
      for (final capability in stockShaped) {
        expect(
          service.has(capability),
          isFalse,
          reason: 'Service must not keep $capability',
        );
      }
    });

    test('Retail keeps every stock capability', () {
      final retail = resolveCategoryCapabilities('HARDWARE', 'Retail');
      expect(retail.has(CategoryCapability.productCatalog), isTrue);
      expect(retail.has(CategoryCapability.inventory), isTrue);
      expect(retail.has(CategoryCapability.barcode), isTrue);
    });

    test('Wholesale trades the same catalogue, at volume', () {
      // No wholesale pricing exists in the schema, so narrowing here would be an
      // assumption the backend cannot honour.
      final wholesale = resolveCategoryCapabilities('HARDWARE', 'Wholesale');
      expect(wholesale.has(CategoryCapability.productCatalog), isTrue);
      expect(wholesale.has(CategoryCapability.inventory), isTrue);
    });

    test('the combined type behaves like both', () {
      for (final type in ['Retail + Wholesale', 'Retail + Wholesale ']) {
        final resolved = resolveCategoryCapabilities('HARDWARE', type);
        expect(resolved.has(CategoryCapability.productCatalog), isTrue, reason: type);
      }
    });

    test('an unknown type stays permissive rather than locking the shop out', () {
      // Deliberate: hiding a capability wrongly is worse than showing one, since
      // showing it fails at submit and says so.
      final unknown = resolveCategoryCapabilities('HARDWARE', 'Retial');
      expect(unknown.has(CategoryCapability.productCatalog), isTrue);
    });

    test('no offered type ever loses contact or location', () {
      for (final type in kBusinessTypes) {
        final resolved = resolveCategoryCapabilities('HARDWARE', type);
        expect(resolved.has(CategoryCapability.contact), isTrue, reason: type);
        expect(resolved.has(CategoryCapability.location), isTrue, reason: type);
      }
    });
  });
}