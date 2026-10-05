import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/utils/distance_format.dart';

void main() {
  group('the three examples this must produce', () {
    test('850 m stays in metres', () {
      expect(formatMeters(850), '850 m');
      expect(formatKilometers(0.85), '850 m');
    });

    test('1.2 km switches to kilometres', () {
      expect(formatMeters(1200), '1.2 km');
      expect(formatKilometers(1.2), '1.2 km');
    });

    test('4.8 km keeps its decimal', () {
      expect(formatMeters(4800), '4.8 km');
      expect(formatKilometers(4.8), '4.8 km');
    });
  });

  group('the unit switch at 1 km', () {
    test('999 m rounds up into kilometres, never "1000 m"', () {
      // "1000 m" is a silly way to say "1 km", and the nearest-10 rounding
      // lands 999 on exactly that boundary.
      expect(formatMeters(999), '1 km');
      expect(formatMeters(999), isNot('1000 m'));
    });

    test('990 m still reads in metres', () {
      expect(formatMeters(990), '990 m');
    });

    test('1000 m is the first kilometre', () {
      expect(formatMeters(1000), '1 km');
      expect(formatMeters(1001), '1 km');
    });

    test('999 m and 1 km converge, by design', () {
      // 999 rounds up to 1 km, so these two are intentionally identical.
      // Pinned because it reads like a bug and someone will "fix" it.
      expect(formatMeters(999), formatMeters(1000));
    });
  });

  group('metres are rounded to the nearest 10', () {
    test('a GPS-precision value is not implied', () {
      // 847.3 m must not render as "847.3 m": the fix is not that accurate.
      expect(formatMeters(847.3), '850 m');
      expect(formatMeters(847), '850 m');
      expect(formatMeters(844), '840 m');
      expect(formatMeters(4), '0 m');
    });

    test('small values do not produce a negative round', () {
      expect(formatMeters(4), '0 m');
      expect(formatMeters(0), '0 m');
    });
  });

  group('trailing zeros are dropped, not shown', () {
    test('5.0 km reads as "5 km"', () {
      expect(formatMeters(5000), '5 km');
      expect(formatKilometers(5), '5 km');
    });

    test('but a real decimal survives', () {
      expect(formatMeters(5800), '5.8 km');
      expect(formatMeters(1490), '1.5 km');
    });

    test('1.0 km is "1 km", not "1.0 km"', () {
      expect(formatMeters(1000), isNot(contains('.0')));
    });
  });

  group('precision drops above 10 km', () {
    test('whole kilometres, because 23.4 implies needless precision', () {
      expect(formatMeters(23400), '23 km');
      expect(formatMeters(12300), '12 km');
    });

    test('at 10 km the decimal drops away entirely', () {
      expect(formatMeters(10000), '10 km');
      expect(formatMeters(12300), '12 km');
    });
  });

  group('unknown is honest, never "0 km"', () {
    test('the backend 0 sentinel yields nothing to render', () {
      // This is the exact value the API sends for an unresolvable distance.
      expect(formatKilometers(0), '');
      expect(formatKilometers(0.0), '');
    });

    test('null yields nothing', () {
      expect(formatKilometers(null), '');
      expect(formatMeters(null), '');
    });

    test('negative and NaN are rejected rather than rendered', () {
      expect(formatMeters(-5), '');
      expect(formatKilometers(-1), '');
      expect(formatMeters(double.nan), '');
    });
  });

  group('style', () {
    test('compact is the default', () {
      expect(formatMeters(1200), '1.2 km');
    });

    test('withUnitSuffix reads as a phrase', () {
      expect(
        formatMeters(1200, style: DistanceStyle.withUnitSuffix),
        '1.2 km away',
      );
    });

    test('the suffix style applies to the metres branch too', () {
      expect(formatMeters(850, style: DistanceStyle.withUnitSuffix), '850 m');
    });
  });

  group('never leaks a float artefact', () {
    test('a value that has been through arithmetic still renders cleanly', () {
      // The bug this replaces: `'${shop.distanceInKm} km away'` printed
      // 0.30000000000000004 for exactly this kind of value.
      final accumulated = 0.1 + 0.2; // 0.30000000000000004
      final rendered = formatKilometers(accumulated);
      // Under 1 km the rule is metres, so 0.3 km reads "300 m".
      expect(rendered, '300 m');
      expect(rendered, isNot(contains('0000000')));
    });

    test('a long tail of thirds is rounded, not echoed', () {
      expect(formatKilometers(10 / 3), '3.3 km');
    });
  });

  group('unit entry points agree when given the same distance', () {
    test('metres and kilometres must not disagree', () {
      for (final m in [50, 400, 850, 999, 1000, 1200, 4800, 9999, 23400]) {
        expect(
          formatMeters(m),
          formatKilometers(m / 1000),
          reason: '$m m vs ${m / 1000} km',
        );
      }
    });
  });
}
