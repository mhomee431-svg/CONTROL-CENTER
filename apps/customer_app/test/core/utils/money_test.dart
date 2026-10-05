import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/utils/money.dart';

void main() {
  group('the requested format', () {
    test('a whole-rupee amount reads ₹248', () {
      expect(formatInr(248), '₹248');
      expect(formatInr('248'), '₹248');
      expect(formatInr(248.0), '₹248');
    });

    test('Indian digit grouping, not Western', () {
      // The single most visible correctness point: en_US would render
      // ₹120,000 for this value, which is simply the wrong number to show an
      // Indian customer.
      expect(formatInr(120000), '₹1,20,000');
      expect(formatInr(10000000), '₹1,00,00,000');
    });

    test('paise appear only when they exist', () {
      expect(formatInr(248.5), '₹248.50');
      expect(formatInr(248.05), '₹248.05');
      expect(formatInr(248.0), '₹248');
    });
  });

  group('no floating-point drift in arithmetic', () {
    test('ten 10-paise items sum to exactly ₹1', () {
      // 0.1 + 0.2 == 0.30000000000000004 in IEEE-754. In paise this is exact.
      var total = Money.zero;
      for (var i = 0; i < 10; i++) {
        total = total + const Money.fromPaise(10);
      }
      expect(total.paise, 100);
      expect(total.formatted, '₹1');
    });

    test('a cart of odd prices never produces a phantom paisa', () {
      var total = Money.zero;
      for (final p in [333, 333, 333]) {
        total = total + Money.fromPaise(p);
      }
      expect(total.paise, 999);
      expect(total.formatted, '₹9.99');
    });

    test('0.1 + 0.2 expressed in rupees is exact', () {
      final a = Money.parse(0.1)!;
      final b = Money.parse(0.2)!;
      expect((a + b).paise, 30);
    });

    test('multiplication is integer-exact', () {
      expect((const Money.rupees(248) * 3).formatted, '₹744');
    });
  });

  group('parsing is safe', () {
    test('backend strings with symbols and separators', () {
      expect(Money.parse('₹1,248.00')!.formatted, '₹1,248');
      expect(Money.parse(' 248.50 ')!.paise, 24850);
      expect(Money.parse('INR 99')!.formatted, '₹99');
    });

    test('accounting negatives', () {
      expect(Money.parse('(248.00)')!.paise, -24800);
      // Sign goes BEFORE the symbol. `NumberFormat.currency` produces
      // "-₹99", which is the Indian/accounting convention; "₹-99" is not.
      expect(Money.parse('-99')!.formatted, '-₹99');
    });

    test('unparseable input is null, never ₹0', () {
      // A price that renders ₹0 because parsing failed is worse than one that
      // renders "—".
      for (final bad in [null, '', '   ', 'abc', '-', '.', '1.2.3']) {
        expect(Money.parse(bad), isNull, reason: '$bad');
      }
      expect(formatInr('abc'), Money.unknownText);
    });

    test('sub-paise precision is handled without exploding', () {
      // The string path is exact: it never touches a double.
      expect(Money.parse('1.9999')!.paise, 199);

      // The double path documents WHY strings and paise exist. 1.005 is not
      // representable in IEEE-754 — it is really 1.00499999999999989... — so
      // 1.005 * 100 == 100.49999999999999 and rounds DOWN to 100 paise.
      // Nothing here has "exploded"; the input simply is not what it looks
      // like. Construct via `fromPaise` or a backend string when the exact
      // amount matters.
      expect(Money.parse(1.005)!.paise, 100);
    });

    test('empty and bare-dot fractions are tolerated', () {
      expect(Money.parse('248.')!.formatted, '₹248');
      expect(Money.parse('.5')!.paise, 50);
    });
  });

  group('comparison and identity', () {
    test('equality is by paise, not by double identity', () {
      expect(const Money.rupees(248), Money.parse(248.0));
      expect(const Money.rupees(248).hashCode, Money.parse('248.00').hashCode);
    });

    test('ordering works', () {
      expect(const Money.rupees(99) < const Money.rupees(100), isTrue);
      expect(const Money.rupees(100) > const Money.rupees(99), isTrue);
      expect(Money.zero.isZero, isTrue);
    });
  });

  group('exact formatting for totals and receipts', () {
    test('always two decimals', () {
      expect(const Money.rupees(248).formattedExact, '₹248.00');
      expect(const Money.fromPaise(24850).formattedExact, '₹248.50');
    });
  });

  group('the old call-site bugs are fixed by this', () {
    test('toStringAsFixed(0) lost paise; formatInr does not', () {
      // The pre-existing behaviour at three call sites rounded 99.50 to "100".
      // That is not a rounding preference, it is a different price.
      expect((99.50).toStringAsFixed(0), '100');
      expect(formatInr(99.50), '₹99.50');
    });

    test('a long amount keeps its paise too', () {
      expect(formatInr(1234.56), '₹1,234.56');
    });
  });
}
