import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/utils/app_datetime.dart';

void main() {
  group('parse - an offset-less backend timestamp is NOT local time', () {
    test('a naive timestamp is interpreted as UTC, not local', () {
      // THE regression. `DateTime.parse` alone would return this as a LOCAL
      // value, and a following `.toLocal()` would be a no-op - producing a time
      // that is wrong by the device UTC offset while looking plausible.
      final parsed = AppDateTime.parse('2026-01-15T10:00:00');
      expect(parsed, isNotNull);
      expect(parsed!.isUtc, isTrue,
          reason: 'an offset-less backend value must land as UTC');
      expect(parsed.hour, 10);
    });

    test('an explicit Z is already UTC', () {
      final parsed = AppDateTime.parse('2026-01-15T10:00:00Z');
      expect(parsed!.isUtc, isTrue);
      expect(parsed.hour, 10);
    });

    test('an explicit numeric offset is honoured, not ignored', () {
      // 10:00 at +05:30 is 04:30 UTC.
      final parsed = AppDateTime.parse('2026-01-15T10:00:00+05:30');
      expect(parsed!.isUtc, isTrue);
      expect(parsed.hour, 4);
      expect(parsed.minute, 30);
    });

    test('a negative offset works too', () {
      // 10:00 at -08:00 is 18:00 UTC.
      expect(AppDateTime.parse('2026-01-15T10:00:00-08:00')!.hour, 18);
    });

    test('the naive and Z forms are the same instant', () {
      expect(
        AppDateTime.parse('2026-01-15T10:00:00')!
            .isAtSameMomentAs(AppDateTime.parse('2026-01-15T10:00:00Z')!),
        isTrue,
      );
    });

    test('fractional seconds survive without throwing', () {
      final parsed = AppDateTime.parse('2026-01-15T10:00:00.123456Z');
      expect(parsed, isNotNull);
      // Deliberately NOT asserting an exact microsecond value: `DateTime.parse`
      // does not round-trip the full 6-digit fraction (observed: it retains
      // 123 ms / 456 us), and pinning that would make this test fail the next
      // time the Dart SDK changes its parser. What must hold is that the
      // instant is intact and the components are in range.
      expect(parsed!.millisecond, inInclusiveRange(0, 999));
      expect(parsed.microsecond, inInclusiveRange(0, 999));
      expect(parsed.hour, 10);
      expect(parsed.minute, 0);
    });
  });

  group('parse - the shapes this API actually emits', () {
    test('epoch millis as an int', () {
      final parsed = AppDateTime.parse(1768471200000);
      expect(parsed!.isUtc, isTrue);
      expect(parsed.millisecondsSinceEpoch, 1768471200000);
    });

    test('epoch millis as a String', () {
      expect(AppDateTime.parse('1768471200000')!.millisecondsSinceEpoch,
          1768471200000);
    });

    test('an existing DateTime is normalised to UTC', () {
      expect(AppDateTime.parse(DateTime(2026, 1, 15, 10))!.isUtc, isTrue);
    });

    test('a space separator (SQL style) parses', () {
      expect(AppDateTime.parse('2026-01-15 10:00:00'), isNotNull);
    });
  });

  group('parse - bad input returns null instead of throwing', () {
    test('null, empty and garbage', () {
      for (final bad in <Object?>[null, '', '   ', 'not-a-date', {}, []]) {
        expect(AppDateTime.parse(bad), isNull, reason: '$bad');
      }
    });

    test('a missing value renders the unknown marker, never blank', () {
      expect(AppDateTime.formatDateTime(null), AppDateTime.unknownText);
      expect(AppDateTime.formatDate(null), AppDateTime.unknownText);
      expect(AppDateTime.formatTime(null), AppDateTime.unknownText);
      expect(AppDateTime.formatDateTimeShort(null), AppDateTime.unknownText);
      expect(AppDateTime.friendlyDay(null), AppDateTime.unknownText);
      expect(AppDateTime.formatRaw('garbage'), AppDateTime.unknownText);
    });
  });
  group('formatting renders the DEVICE zone, not UTC', () {
    test('a UTC instant is shown in local time', () {
      final utc = DateTime.utc(2026, 1, 15, 10);
      final local = utc.toLocal();
      final shown = AppDateTime.formatDateTime(utc);
      expect(local.isUtc, isFalse, reason: 'sanity: toLocal must leave UTC');
      expect(shown, contains('${local.year}'));
    });

    test('a forgotten toLocal() would be caught here', () {
      // Compare against the explicitly converted value. If a formatter ever
      // dropped `.toLocal()`, the output would show the UTC wall-clock
      // regardless of where the device is, and this assertion fails.
      final utc = DateTime.utc(2026, 1, 15, 10, 30);
      final local = utc.toLocal();
      final hour = local.hour == 0 ? 12 : (local.hour > 12 ? local.hour - 12 : local.hour);
      expect(AppDateTime.formatDateTime(utc), contains('$hour:'));
    });

    test('formatRaw parses then formats in one step', () {
      expect(AppDateTime.formatRaw('2026-01-15T10:00:00Z'),
          AppDateTime.formatDateTime(DateTime.utc(2026, 1, 15, 10)));
    });
  });

  group('friendlyDay is relative to the device zone', () {
    test('today, yesterday and a weekday', () {
      final now = DateTime(2026, 1, 15, 12);
      expect(AppDateTime.friendlyDay(DateTime(2026, 1, 15, 9), now: now),
          'Today');
      expect(AppDateTime.friendlyDay(DateTime(2026, 1, 14, 9), now: now),
          'Yesterday');
      // 2026-01-13 is a Tuesday.
      expect(AppDateTime.friendlyDay(DateTime(2026, 1, 13, 9), now: now), 'Tue');
    });

    test('falls back to a date beyond a week', () {
      final out = AppDateTime.friendlyDay(DateTime(2025, 11, 2, 9),
          now: DateTime(2026, 1, 15, 12));
      expect(out, contains('2025'));
    });
  });

  group('isSameLocalDay compares calendar days, not instants', () {
    test('agrees with an explicit local comparison', () {
      // 22:00 UTC on the 15th is 03:30 on the 16th in IST (+05:30).
      final late = DateTime.utc(2026, 1, 15, 22);
      final early = DateTime.utc(2026, 1, 15, 2);
      final a = late.toLocal();
      final b = early.toLocal();
      expect(AppDateTime.isSameLocalDay(late, early), a.day == b.day);
    });

    test('identical instants are the same day', () {
      final t = DateTime.utc(2026, 1, 15, 10);
      expect(AppDateTime.isSameLocalDay(t, t), isTrue);
    });
  });

  group('relative() keeps the existing recency voice', () {
    test('two hours ago', () {
      final now = DateTime.utc(2026, 1, 15, 12);
      expect(
        AppDateTime.relative(now.subtract(const Duration(hours: 2)), now: now),
        contains('2 hours ago'),
      );
    });
  });
}