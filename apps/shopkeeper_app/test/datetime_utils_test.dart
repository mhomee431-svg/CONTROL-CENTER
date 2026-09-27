import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/utils/datetime_utils.dart';

void main() {
  group('DateTimeUtils.tryParseToLocal', () {
    test('converts a UTC timestamp to local time', () {
      final parsed = DateTimeUtils.tryParseToLocal('2026-03-01T12:00:00Z')!;
      expect(parsed.isUtc, isFalse);
      expect(
        parsed.millisecondsSinceEpoch,
        DateTime.utc(2026, 3, 1, 12).millisecondsSinceEpoch,
      );
    });

    test('keeps an already-local timestamp untouched', () {
      final local = DateTime(2026, 3, 1, 12);
      expect(DateTimeUtils.tryParseToLocal(local), local);
    });

    test(
      'does not re-shift a local DateTime that happens to parse as a string',
      () {
        final parsed = DateTimeUtils.tryParseToLocal('2026-03-01T12:00:00')!;
        expect(parsed.isUtc, isFalse);
        expect(parsed, DateTime(2026, 3, 1, 12));
      },
    );

    test(
      'returns null for missing or malformed values instead of throwing',
      () {
        expect(DateTimeUtils.tryParseToLocal(null), isNull);
        expect(DateTimeUtils.tryParseToLocal(''), isNull);
        expect(DateTimeUtils.tryParseToLocal('   '), isNull);
        expect(DateTimeUtils.tryParseToLocal('not-a-date'), isNull);
        expect(DateTimeUtils.tryParseToLocal(42), isNull);
      },
    );
  });

  group('DateTimeUtils.formatRelativeOrLocal', () {
    final now = DateTime(2026, 3, 10, 15, 30);

    String format(DateTime? value, {String nullLabel = 'Not updated yet'}) =>
        DateTimeUtils.formatRelativeOrLocal(
          value,
          referenceNow: now,
          nullLabel: nullLabel,
        );

    test('renders the null label when there is no timestamp', () {
      expect(format(null), 'Not updated yet');
      expect(format(null, nullLabel: '-'), '-');
    });

    test('renders just now under a minute', () {
      expect(format(now.subtract(const Duration(seconds: 5))), 'just now');
      expect(format(now.subtract(const Duration(seconds: 59))), 'just now');
    });

    test('renders minutes and hours', () {
      expect(format(now.subtract(const Duration(minutes: 15))), '15 min ago');
      expect(format(now.subtract(const Duration(hours: 5))), '5 h ago');
    });

    test(
      'a UTC timestamp is compared as an instant, not as wall-clock fields',
      () {
        // The API returns UTC, so the age must come from the instant. Deriving
        // the stamp from the local reference keeps this exact on any device
        // timezone, and the epoch check proves the UTC -> local shift happened
        // rather than the raw fields being reinterpreted.
        final utc = now.toUtc().subtract(const Duration(minutes: 15));
        expect(format(utc), '15 min ago');
        expect(
          DateTimeUtils.tryParseToLocal(utc)!.millisecondsSinceEpoch,
          now.millisecondsSinceEpoch -
              const Duration(minutes: 15).inMilliseconds,
        );
      },
    );

    test('keeps the relative label for a stamp earlier the same day', () {
      // 09:05 is 6h25m before the 15:30 reference, so it is still described
      // relatively — the calendar-day forms only start once the age passes a
      // day. Asserting "Today 09:05" here would contradict the "5 h ago" case
      // above, and nothing in the app renders a "Today" prefix.
      expect(format(DateTime(2026, 3, 10, 9, 5)), '6 h ago');
    });

    test('labels the previous day with its local clock time', () {
      // 22:40 the day before is 16h50m old, so it is still under a day and
      // keeps the relative label; a genuinely day-old stamp is 09:30 on the
      // 9th, which is 30h before the reference.
      expect(format(DateTime(2026, 3, 9, 22, 40)), '16 h ago');
      expect(format(DateTime(2026, 3, 9, 9, 30)), 'Yesterday 09:30');
    });

    test('drops the year for older dates in the current year', () {
      expect(format(DateTime(2026, 1, 2, 10, 0)), '2 Jan, 10:00');
    });

    test('keeps the year once the timestamp is from a previous year', () {
      expect(format(DateTime(2025, 12, 31, 23, 59)), '31 Dec 2025, 23:59');
    });

    test('shows an absolute local time for a future (clock-skewed) stamp', () {
      final future = now.add(const Duration(hours: 2));
      expect(format(future), contains('${future.day}'));
      expect(format(future), isNot(contains('ago')));
    });
  });

  group('DateTimeUtils.formatShortDate', () {
    test('formats a local date and falls back to an em dash', () {
      expect(DateTimeUtils.formatShortDate(DateTime(2026, 3, 1)), '1 Mar 2026');
      expect(DateTimeUtils.formatShortDate(null), '—');
    });
  });

  group('DateTimeUtils.formatFreshness (unified data-age vocabulary)', () {
    final now = DateTime(2026, 3, 10, 15, 30);

    test('each surface owns its prefix and its null label', () {
      expect(
        DateTimeUtils.formatInventoryFreshness(null, referenceNow: now),
        'Inventory not updated yet',
      );
      expect(
        DateTimeUtils.formatPriceFreshness(null, referenceNow: now),
        'Price not updated yet',
      );
      expect(
        DateTimeUtils.formatPosSyncFreshness(null, referenceNow: now),
        'No POS sync yet',
      );
      expect(
        DateTimeUtils.formatFreshness('Stock', null,
            referenceNow: now, nullLabel: '-'),
        '-',
      );
    });

    test('renders "just now" under a minute and "N min ago" under an hour', () {
      expect(
        DateTimeUtils.formatInventoryFreshness(
          now.subtract(const Duration(seconds: 30)),
          referenceNow: now,
        ),
        'Inventory updated just now',
      );
      expect(
        DateTimeUtils.formatInventoryFreshness(
          now.subtract(const Duration(minutes: 15)),
          referenceNow: now,
        ),
        'Inventory updated 15 min ago',
      );
    });

    test('crosses to calendar words once the age passes an hour', () {
      // 09:05 is 6h25m old but still today → "today".
      expect(
        DateTimeUtils.formatPriceFreshness(
          DateTime(2026, 3, 10, 9, 5),
          referenceNow: now,
        ),
        'Price updated today',
      );
      // 09:30 the day before is over a day old → "yesterday".
      expect(
        DateTimeUtils.formatPosSyncFreshness(
          DateTime(2026, 3, 9, 9, 30),
          referenceNow: now,
        ),
        'Last POS sync yesterday',
      );
      // Even a stamp that crossed midnight by minutes is honestly "yesterday"
      // — the label claims the calendar, not the elapsed hours.
      expect(
        DateTimeUtils.formatInventoryFreshness(
          DateTime(2026, 3, 9, 22, 40),
          referenceNow: now,
        ),
        'Inventory updated yesterday',
      );
    });

    test('older stamps show their date', () {
      expect(
        DateTimeUtils.formatInventoryFreshness(
          DateTime(2026, 1, 2, 10, 0),
          referenceNow: now,
        ),
        'Inventory updated 2 Jan 2026',
      );
    });

    test('a UTC timestamp ages as an instant, not as wall-clock fields', () {
      final utc = now.toUtc().subtract(const Duration(minutes: 15));
      expect(
        DateTimeUtils.formatInventoryFreshness(utc, referenceNow: now),
        'Inventory updated 15 min ago',
      );
    });

    test('a future (clock-skewed) stamp never claims an age', () {
      final future = now.add(const Duration(hours: 2));
      final label = DateTimeUtils.formatPriceFreshness(
        future,
        referenceNow: now,
      );
      expect(label, startsWith('Price updated '));
      expect(label, isNot(contains('ago')));
      expect(label, isNot(contains('today')));
    });
  });

  group('DateTimeUtils.isStale (the stale indicator)', () {
    final now = DateTime(2026, 3, 10, 15, 30);

    test('null is NOT stale — there is no evidence either way', () {
      expect(DateTimeUtils.isStale(null, referenceNow: now), isFalse);
    });

    test('crosses the 24h threshold', () {
      expect(
        DateTimeUtils.isStale(
          now.subtract(const Duration(hours: 23)),
          referenceNow: now,
        ),
        isFalse,
      );
      expect(
        DateTimeUtils.isStale(
          now.subtract(const Duration(hours: 25)),
          referenceNow: now,
        ),
        isTrue,
      );
    });

    test('honours a custom threshold and ignores future stamps', () {
      expect(
        DateTimeUtils.isStale(
          now.subtract(const Duration(hours: 2)),
          threshold: const Duration(hours: 1),
          referenceNow: now,
        ),
        isTrue,
      );
      expect(
        DateTimeUtils.isStale(now.add(const Duration(days: 3)),
            referenceNow: now),
        isFalse,
      );
    });
  });
}
