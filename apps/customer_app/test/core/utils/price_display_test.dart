import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/utils/money.dart';
import 'package:hyperlocal_app/core/utils/price_display.dart';

void main() {
  group('a real discount is detected and labelled', () {
    test('MRP 499 sold at 249 is a 50% discount', () {
      final p = PriceDisplay.fromBackend(mrp: 499, price: 249);
      expect(p.hasDiscount, isTrue);
      expect(p.discountPercent, 50);
      expect(p.savings!.formatted, '₹250');
      expect(PriceLabels.savingsLabel(p), 'Save ₹250 (50% OFF)');
    });

    test('percentages round to whole numbers, not noise', () {
      // 299 -> 250 is 16.4%, shown as 16.
      final p = PriceDisplay.fromBackend(mrp: 299, price: 250);
      expect(p.discountPercent, 16);
      expect(p.discountPercent, lessThanOrEqualTo(100));
    });

    test('paise are preserved end to end', () {
      final p = PriceDisplay.fromBackend(mrp: '99.50', price: '49.75');
      expect(p.discountPercent, 50);
      expect(p.savings!.formatted, '₹49.75');
    });
  });

  group('NO discount is invented when the data does not support one', () {
    test('price equal to MRP is not a discount', () {
      final p = PriceDisplay.fromBackend(mrp: 249, price: 249);
      expect(p.hasDiscount, isFalse);
      expect(p.discountPercent, isNull);
      expect(p.savings, isNull);
      expect(PriceLabels.savingsLabel(p), isEmpty);
    });

    test('price ABOVE MRP is not a discount either', () {
      // Nonsense data must not render as "−9% OFF" or a 0% badge.
      final p = PriceDisplay.fromBackend(mrp: 249, price: 300);
      expect(p.hasDiscount, isFalse);
      expect(p.discountPercent, isNull);
      expect(
        p.hasOriginalButNoDiscount,
        isTrue,
        reason: 'MRP is still true information and may be shown',
      );
    });

    test('no current price means no discount', () {
      final p = PriceDisplay.fromBackend(mrp: 499, price: 0);
      expect(p.hasDiscount, isFalse);
      expect(p.discountPercent, isNull);
      expect(p.hasNoCurrentPrice, isTrue);
    });

    test('missing MRP means no discount', () {
      final p = PriceDisplay.fromBackend(price: 249);
      expect(p.hasDiscount, isFalse);
      expect(p.discountPercent, isNull);
    });

    test('both missing yields nothing rather than a fabricated 0%', () {
      final p = PriceDisplay.fromBackend();
      expect(p.hasDiscount, isFalse);
      expect(p.discountPercent, isNull);
      expect(p.originalPrice, isNull);
      expect(p.currentPrice, isNull);
    });

    test('negative and garbage input is discarded, not rendered', () {
      for (final bad in [-100, 'abc', '', null]) {
        final p = PriceDisplay.fromBackend(mrp: bad, price: bad);
        expect(p.currentPrice, isNull, reason: '$bad');
        expect(p.discountPercent, isNull, reason: '$bad');
      }
    });
  });

  group('offer price from the backend is trusted over a derivation', () {
    test('offerPrice wins when supplied', () {
      // The backend knows the real payable amount for a promotion. Deriving it
      // from mrp would be the guess this class exists to prevent.
      final p = PriceDisplay.fromBackend(mrp: 499, price: 249, offerPrice: 199);
      expect(p.currentPrice!.formatted, '₹199');
      expect(p.discountPercent, 60);
    });

    test('falls back to price when offerPrice is unusable', () {
      final p = PriceDisplay.fromBackend(mrp: 499, price: 249, offerPrice: 0);
      expect(p.currentPrice!.formatted, '₹249');
      expect(p.discountPercent, 50);
    });
  });

  group('the three prices stay distinguishable', () {
    test('original and current are separate values', () {
      final p = PriceDisplay.fromBackend(mrp: 499, price: 249);
      expect(p.originalPrice!.formatted, '₹499');
      expect(p.currentPrice!.formatted, '₹249');
      expect(p.originalPrice, isNot(p.currentPrice));
    });

    test('labels name each part explicitly', () {
      expect(PriceLabels.original, 'MRP');
      expect(PriceLabels.current, 'Price');
      expect(PriceLabels.offer, 'Offer price');
    });

    test('current price is never defaulted to MRP', () {
      // The single most misleading thing this API could do: with no live offer,
      // MRP must NOT become the "price".
      final p = PriceDisplay.fromBackend(mrp: 499);
      expect(p.currentPrice, isNull);
      expect(p.hasNoCurrentPrice, isTrue);
    });
  });

  group('percentage arithmetic is integer, not float', () {
    test('an amount that would drift as a double still lands exactly', () {
      // 0.1-style drift: (299-250)*100/299 as doubles is not reliably 16.
      final p = PriceDisplay.fromBackend(mrp: 299, price: 250);
      expect(p.discountPercent, 16);
      expect(Money.parse(p.savings!.asRupees)!.paise, 4900);
    });
  });
}
