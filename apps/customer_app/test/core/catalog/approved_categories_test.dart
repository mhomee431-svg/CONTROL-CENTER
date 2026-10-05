import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/catalog/approved_categories.dart';

/// Guards the one category rule the DATABASE cannot express.
///
/// The home feed used to filter its backend categories through
/// `ApprovedCategories.isApproved` — an ALLOW-list. That is the thing this task
/// removed, because it meant an admin publishing a category could never surface
/// it without a new app build, and nothing failed when they tried.
///
/// What replaced it is a deny-list, so these tests are the other half of that
/// trade: unknown categories must now be ALLOWED, while the two exclusions the
/// product's own rules call out must still be blocked.
void main() {
  group('product browsing is a deny-list, not an allow-list', () {
    test('an unknown, newly published category is browsable', () {
      // THE regression. Under the allow-list this was false, which is precisely
      // why a new category could never appear without an app release.
      expect(ApprovedCategories.isProductBrowsable('Pet Supplies'), isTrue);
      expect(ApprovedCategories.isProductBrowsable('Organic Produce'), isTrue);
      expect(
        ApprovedCategories.isProductBrowsable('Something Brand New'),
        isTrue,
      );
    });

    test('grocery is never browsable', () {
      // Stated in this file's own header: grocery must never appear.
      expect(
        ApprovedCategories.isProductBrowsable('Grocery & General Food'),
        isFalse,
      );
    });

    test('restaurants are discovery, not product delivery', () {
      expect(ApprovedCategories.isProductBrowsable('Restaurants'), isFalse);
    });

    test('matching ignores case and surrounding whitespace', () {
      expect(ApprovedCategories.isProductBrowsable('  restaurants '), isFalse);
      expect(
        ApprovedCategories.isProductBrowsable('GROCERY & GENERAL FOOD'),
        isFalse,
      );
      expect(ApprovedCategories.isProductBrowsable('  Pet Supplies '), isTrue);
    });

    test('every approved PRODUCT category stays browsable', () {
      // Sanity: the deny-list must not accidentally block the product catalogue
      // the app actually ships with. Scoped to product-typed entries, because
      // 'Restaurants' and the transport services sit in the same compiled list
      // and are deliberately NOT product-discovery categories.
      final productNames = ApprovedCategories.all
          .where((c) => c.type == ApprovedCategoryType.product)
          .map((c) => c.name);

      expect(productNames, isNotEmpty);
      for (final name in productNames) {
        expect(
          ApprovedCategories.isProductBrowsable(name),
          isTrue,
          reason:
              '"$name" is an approved product category and must be browsable',
        );
      }
    });

    test('the deny-list overrides the compiled list', () {
      // 'Restaurants' IS in `ApprovedCategories.names`, so the old allow-list
      // would have let it onto the home screen -- exactly the bug the
      // deny-list fixes. The two lists are now independent.
      expect(ApprovedCategories.names, contains('Restaurants'));
      expect(ApprovedCategories.isProductBrowsable('Restaurants'), isFalse);
    });
  });

  group('the existing helpers still behave', () {
    test('isApproved still recognises the compiled list', () {
      // Kept because the search filter bar and the seeder rely on it; it is no
      // longer the gate for what the customer sees.
      expect(ApprovedCategories.isApproved('Household Goods'), isTrue);
      expect(ApprovedCategories.isApproved('Pet Supplies'), isFalse);
    });

    test('isRestaurant and isService classify by type', () {
      expect(ApprovedCategories.isRestaurant('Restaurants'), isTrue);
      expect(ApprovedCategories.isService('Transport'), isTrue);
      expect(ApprovedCategories.isService('Household Goods'), isFalse);
    });

    test('find returns null for an unknown name', () {
      expect(ApprovedCategories.find('Pet Supplies'), isNull);
    });
  });
}
