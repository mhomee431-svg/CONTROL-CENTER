import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/presentation/widgets/inventory_shared.dart';
import 'package:hyperlocal_shopkeeper_app/features/offers/domain/offer_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/pricing/presentation/screens/update_price_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/pricing/presentation/widgets/pricing_shared.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_form_rules.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';

import 'fakes.dart';

/// Spec §132 PRICE TEST CASES, one group per named case: valid price, zero,
/// invalid negative price, decimal handling, price conflict, offer validation.
///
/// Two specs drive the rules under test:
///   * §36 PRICE UPDATE — "Selling Price >= 0 / MRP >= 0", and "Do not allow
///     invalid relationships where backend rules prohibit them".
///   * §35 PRICING — "Money values must use proper decimal/string handling. Do
///     not use floating point for financial presentation/calculation where data
///     handling would lose precision."
///
/// The "zero" case is the one that was broken: the Update Price screen kept a
/// private copy of the validation and rejected `price <= 0`, while the backend
/// (`ge=0`) and the app's own shared `ProductFormRules` allow it — so a product
/// creatable at zero could never be edited back to zero.
void main() {
  ShopProductItem row({int id = 11, String name = 'Rice 5kg', double price = 90}) =>
      ShopProductItem(
        id: id,
        name: name,
        status: 'ACTIVE',
        price: price,
        mrp: 120,
        isActive: true,
        isAvailable: true,
        quantity: 10,
        stockStatus: 'IN_STOCK',
      );

  ProviderContainer makeContainer(FakeProductRepo repo) {
    final container = ProviderContainer(overrides: [
      productRepositoryProvider.overrideWithValue(repo),
      inventoryRepositoryProvider.overrideWithValue(repo),
      tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(accessToken: 'test-access-token')),
      selectedShopProvider
          .overrideWith(() => SelectedShopOverride(ownerShop(id: 10))),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  /// Opens Update Price, picks [name] from the picker, and lands on the form.
  Future<FakeProductRepo> openForm(
    WidgetTester tester, {
    String name = 'Rice 5kg',
    double price = 90,
  }) async {
    final repo = FakeProductRepo(items: [row(name: name, price: price)]);
    final container = makeContainer(repo);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: UpdatePriceScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
    return repo;
  }

  Finder priceField() => find.byKey(const Key('update-price-field'));
  Finder mrpField() => find.byKey(const Key('update-price-mrp-field'));
  Finder saveButton() => find.byKey(const Key('update-price-save'));
  Finder errorBanner() => find.byKey(const Key('update-price-error'));

  // ── §132: valid price ─────────────────────────────────────────────────────
  group('valid price', () {
    testWidgets('a whole-number price and MRP are PATCHed through', (tester) async {
      final repo = await openForm(tester);

      await tester.enterText(priceField(), '95');
      await tester.enterText(mrpField(), '120');
      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(repo.lastUpdatedId, 11);
      expect(repo.lastUpdateFields!['price'], 95.0);
      expect(repo.lastUpdateFields!['mrp'], 120.0);
      expect(errorBanner(), findsNothing);
    });

    testWidgets('the MRP is optional — leaving it blank clears it, not breaks it',
        (tester) async {
      final repo = await openForm(tester);

      await tester.enterText(priceField(), '95');
      await tester.enterText(mrpField(), '');
      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(repo.lastUpdateFields!['price'], 95.0);
      expect(repo.lastUpdateFields!.containsKey('mrp'), isFalse);
    });
  });

  // ── §132: zero ────────────────────────────────────────────────────────────
  group('zero', () {
    testWidgets('a price of exactly zero is saved', (tester) async {
      // §36 says "Selling Price >= 0" and the backend schema is `ge=0`. This
      // screen used to reject it with a private `price <= 0` check, so a
      // product that could be CREATED at zero could never be edited back to
      // zero.
      final repo = await openForm(tester);

      await tester.enterText(priceField(), '0');
      await tester.enterText(mrpField(), '120');
      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(errorBanner(), findsNothing);
      expect(repo.lastUpdatedId, 11);
      expect(repo.lastUpdateFields!['price'], 0.0);
    });

    testWidgets('a zero price and a zero MRP together are still legal',
        (tester) async {
      final repo = await openForm(tester);

      await tester.enterText(priceField(), '0');
      await tester.enterText(mrpField(), '0');
      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(errorBanner(), findsNothing);
      expect(repo.lastUpdateFields!['price'], 0.0);
      expect(repo.lastUpdateFields!['mrp'], 0.0);
    });

    test('zero agrees with the shared rule and with the backend', () {
      // The single definition: `ProductFormRules.price` is what the create
      // sheet uses and what mirrors the backend's `ge=0`. Update Price now
      // delegates to it instead of keeping its own opinion.
      expect(ProductFormRules.price('0'), isNull);
      expect(ProductFormRules.price('0.00'), isNull);
      expect(ProductFormRules.price('-1')?.code,
          ProductFormFieldError.priceNegative);
    });
  });

  // ── §132: invalid negative price ──────────────────────────────────────────
  group('invalid negative price', () {
    testWidgets('a negative price is refused with an explanation, not silently saved',
        (tester) async {
      final repo = await openForm(tester);

      await tester.enterText(priceField(), '-50');
      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(errorBanner(), findsOneWidget);
      expect(repo.lastUpdatedId, isNull);
      // The field can HOLD the minus so the message can explain it — matching
      // the create sheet, where `NumericInput.decimal(allowSign: true)` is used
      // for exactly this reason.
      expect(find.text('Price cannot be negative'), findsOneWidget);
    });

    testWidgets('a negative MRP is refused too', (tester) async {
      final repo = await openForm(tester);

      await tester.enterText(priceField(), '95');
      await tester.enterText(mrpField(), '-120');
      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(errorBanner(), findsOneWidget);
      expect(repo.lastUpdatedId, isNull);
    });

    test('non-numeric input is refused rather than coerced to zero', () {
      // A field that cannot parse must NOT fall through to a 0 price — that
      // would turn a typo into a free product.
      expect(ProductFormRules.price('abc')?.code,
          ProductFormFieldError.invalidAmount);
      expect(ProductFormRules.price('')?.code,
          ProductFormFieldError.priceRequired);
      expect(ProductFormRules.price('  ')?.code,
          ProductFormFieldError.priceRequired);
    });
  });

  // ── §132: decimal handling ────────────────────────────────────────────────
  group('decimal handling', () {
    testWidgets('a fractional price survives the round trip intact', (tester) async {
      final repo = await openForm(tester);

      await tester.enterText(priceField(), '95.75');
      await tester.enterText(mrpField(), '120.50');
      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(errorBanner(), findsNothing);
      expect(repo.lastUpdateFields!['price'], 95.75);
      expect(repo.lastUpdateFields!['mrp'], 120.50);
    });

    testWidgets('money is capped at two decimals at the keystroke', (tester) async {
      // §35: money must not carry more precision than a currency needs, so the
      // third decimal is refused rather than shipped as 1.999.
      final repo = await openForm(tester);

      await tester.enterText(priceField(), '10.999');
      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(repo.lastUpdateFields!['price'], 10.99);
    });

    testWidgets('a price renders without floating-point noise', (tester) async {
      // §35 "do not use floating point for financial PRESENTATION": 29.90 must
      // read as "29.9", never "29.899999999999999".
      expect(trimNumber(29.90), '29.9');
      expect(trimNumber(30.0), '30');
      expect(trimNumber(119.50), '119.5');
      expect(moneyLabel(249.99), '₹249.99');

      // The seeded field must show the same thing, or reopening the screen
      // would show the shopkeeper something they never typed.
      final item = ShopProductItem(
        id: 1,
        name: 'Tea',
        status: 'ACTIVE',
        price: 29.90,
        mrp: 39.90,
        isActive: true,
        isAvailable: true,
        quantity: 1,
        stockStatus: 'IN_STOCK',
      );
      final container = makeContainer(FakeProductRepo(items: [item]));
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: UpdatePriceScreen(product: item)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('29.9'), findsOneWidget);
      expect(find.text('39.9'), findsOneWidget);
    });

    test('the implied discount is rounded, never a repeating decimal', () {
      // These ratios are exactly where naive float math leaks
      // (e.g. 19.999999999999996).
      expect(discountPercentOff(120, 90), 25.0);
      expect(discountPercentOff(80, 20), 75.0);
      expect(discountPercentOff(100, 1), 99.0);
      // No MRP, or a price at/above the MRP, means no discount at all.
      expect(discountPercentOff(null, 90), isNull);
      expect(discountPercentOff(90, 90), isNull);
      expect(discountPercentOff(80, 90), isNull);
    });
  });

  // ── §132: price conflict ──────────────────────────────────────────────────
  group('price conflict', () {
    testWidgets('an MRP below the selling price is refused before the round trip',
        (tester) async {
      final repo = await openForm(tester);

      await tester.enterText(priceField(), '95');
      await tester.enterText(mrpField(), '50');
      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(errorBanner(), findsOneWidget);
      expect(find.text('MRP cannot be lower than the selling price'),
          findsOneWidget);
      expect(repo.lastUpdatedId, isNull);
    });

    testWidgets('an MRP exactly equal to the selling price is not a conflict',
        (tester) async {
      // A 0% discount is a perfectly ordinary listing; only UNDERCUTTING is
      // the relationship the backend prohibits (§36).
      final repo = await openForm(tester);

      await tester.enterText(priceField(), '95');
      await tester.enterText(mrpField(), '95');
      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(errorBanner(), findsNothing);
      expect(repo.lastUpdateFields!['mrp'], 95.0);
    });

    testWidgets('a server-side conflict is surfaced verbatim, not as a generic error',
        (tester) async {
      // The client only mirrors the rule; the backend is the authority, and its
      // wording must reach the shopkeeper (§36).
      const refusal = 'MRP cannot be lower than selling price';
      final item = row();
      final repo = FakeProductRepo(
        items: [item],
        onUpdate: (_, _) => throw const ApiException(
            statusCode: 422, message: refusal),
      );
      final container = makeContainer(repo);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: UpdatePriceScreen(product: item)),
      ));
      await tester.pumpAndSettle();

      // Clear the MRP so the CLIENT rule has nothing to catch — otherwise
      // `mrp(120) < price(200)` blocks the save before the wire and the
      // server's own wording would never be reached. The backend stays the
      // authority for whatever the mirror cannot see.
      await tester.enterText(mrpField(), '');
      await tester.enterText(priceField(), '200');
      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(find.text(refusal), findsOneWidget);
    });

    test('the cross-field rule is shared, not re-implemented per screen', () {
      // The definition lives once, so the create sheet and Update Price cannot
      // drift apart again.
      expect(ProductFormRules.mrp('50', priceText: '95')?.code,
          ProductFormFieldError.mrpBelowPrice);
      expect(ProductFormRules.mrp('95', priceText: '95'), isNull);
      expect(ProductFormRules.mrp('96', priceText: '95'), isNull);
      // With no price typed yet, the cross-field check must stay quiet rather
      // than block on a half-filled form.
      expect(ProductFormRules.mrp('50', priceText: ''), isNull);
    });
  });

  // ── §132: offer validation ────────────────────────────────────────────────
  group('offer validation', () {
    test('a percentage discount must be above 0 and at most 100', () {
      String? pct(String v) => OfferValidators.discount(
          ShopkeeperOfferType.percentageDiscount,
          v,
          null);

      expect(pct('20'), isNull);
      expect(pct('100'), isNull, reason: '100% off is allowed');
      expect(pct('0'), 'Discount % is required');
      expect(pct(''), 'Discount % is required');
      expect(pct('abc'), 'Discount % is required');
      // A discount above 100% would imply a negative payable amount.
      expect(pct('101'), 'Discount % cannot exceed 100');
      expect(pct('-5'), 'Discount % is required');
    });

    test('a flat discount must be positive, and says WHICH mistake it was',
        () {
      // The negative branch used to be unreachable: `value <= 0` returned
      // "is required" first, so a shopkeeper who typed -50 was told they had
      // simply not filled the field in.
      String? flat(String v) => OfferValidators.discount(
          ShopkeeperOfferType.flatDiscount,
          null,
          v);

      expect(flat('25'), isNull);
      expect(flat('-50'), 'Cannot be negative');
      expect(flat('0'), 'Discount amount is required');
      expect(flat(''), 'Discount amount is required');
      expect(flat('abc'), 'Discount amount is required');
    });

    test('a promotional price must be a positive amount', () {
      String? promo(String v) => OfferValidators.discount(
          ShopkeeperOfferType.promotionalPrice,
          null,
          null,
          v);

      expect(promo('99'), isNull);
      expect(promo('99.50'), isNull);
      expect(promo('0'), 'Promotional price is required');
      expect(promo('-1'), 'Promotional price is required');
    });

    test('a promo price falls back to the flat field when the promo box is empty',
        () {
      // The validator reads `rawPromo ?? rawValue` so the one field that is on
      // screen for this type is the one that gets judged.
      expect(
        OfferValidators.discount(
            ShopkeeperOfferType.promotionalPrice, null, '149'),
        isNull,
      );
    });

    test('dates are validated: both required, and the end must follow the start',
        () {
      // §38 "Validate dates."
      final start = DateTime(2026, 3, 1);
      final end = DateTime(2026, 3, 10);

      expect(OfferValidators.period(start, end), isNull);
      expect(OfferValidators.period(start, null), 'Select both dates');
      expect(OfferValidators.period(null, end), 'Select both dates');
      expect(OfferValidators.period(null, null), 'Select both dates');
      // Same-day is not a range; and a reversed range would publish an offer
      // that is already over before it starts.
      expect(OfferValidators.period(start, start),
          'End date must be after the start date');
      expect(OfferValidators.period(end, start),
          'End date must be after the start date');
    });

    test('a title is required and bounded by the backend maximum', () {
      expect(OfferValidators.title('Monsoon Sale'), isNull);
      expect(OfferValidators.title('  '), 'Offer title is required');
      expect(OfferValidators.title(null), 'Offer title is required');
      expect(OfferValidators.title('x' * 256), 'Title is too long');
      expect(OfferValidators.title('x' * 255), isNull);
    });
  });
}