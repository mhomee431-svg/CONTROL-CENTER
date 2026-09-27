import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/utils/relative_time.dart';

void main() {
  final now = DateTime(2026, 9, 27, 12, 0, 0);

  group('formatLastUpdated', () {
    test('always uses the mandated "Last updated" prefix', () {
      // The spec's literal wording. Asserted on every branch because this is the
      // only signal that tells a customer they are looking at a snapshot.
      final samples = <DateTime?>[
        now,
        now.subtract(const Duration(minutes: 5)),
        now.subtract(const Duration(hours: 3)),
        now.subtract(const Duration(days: 1)),
        now.subtract(const Duration(days: 40)),
        now.subtract(const Duration(days: 800)),
        null,
      ];
      for (final at in samples) {
        expect(
          formatLastUpdated(at, now: now),
          startsWith('Last updated'),
          reason: 'failed for $at',
        );
      }
    });

    test('a null timestamp says so rather than implying recency', () {
      // Silence here would read as "just now", which is the exact confusion
      // the disclosure exists to prevent.
      expect(
        formatLastUpdated(null, now: now),
        'Last updated at an unknown time',
      );
    });

    test('a future timestamp does not claim to be fresh', () {
      // Clock skew means the age is genuinely unknown; "just now" would be a
      // lie in the customer's favour.
      expect(
        formatLastUpdated(now.add(const Duration(minutes: 5)), now: now),
        'Last updated at an unknown time',
      );
    });

    test('scales wording with the age', () {
      expect(formatLastUpdated(now, now: now), 'Last updated just now');
      expect(
        formatLastUpdated(now.subtract(const Duration(minutes: 5)), now: now),
        'Last updated 5 min ago',
      );
      expect(
        formatLastUpdated(now.subtract(const Duration(hours: 1)), now: now),
        'Last updated 1 hour ago',
      );
      expect(
        formatLastUpdated(now.subtract(const Duration(hours: 5)), now: now),
        'Last updated 5 hours ago',
      );
      expect(
        formatLastUpdated(now.subtract(const Duration(days: 1)), now: now),
        'Last updated yesterday',
      );
      expect(
        formatLastUpdated(now.subtract(const Duration(days: 3)), now: now),
        'Last updated 3 days ago',
      );
      expect(
        formatLastUpdated(now.subtract(const Duration(days: 14)), now: now),
        'Last updated 2 weeks ago',
      );
    });

    test('never collapses old data into a vague label', () {
      // `formatFreshnessText` returns a bare "Stale" past a day. For a cache
      // disclosure that is too little: the customer needs the magnitude to
      // decide whether a price is still worth believing.
      final threeDays = formatLastUpdated(
        now.subtract(const Duration(days: 3)),
        now: now,
      );
      expect(threeDays, isNot(contains('Stale')));
      expect(threeDays, contains('3 days'));
    });
  });
}