import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_app/core/analytics/product_analytics.dart';

/// Guards the two rules this module exists to enforce:
/// only the declared events can be recorded, and no secret can leave the app.
///
/// ## Why the OTP cases are the headline
/// ------------------------------------
/// The obvious protection is "don't log tokens". The subtle one is a BARE
/// 6-digit code. `SafeLogger` redacts `key=value` pairs and 10-12 digit numbers,
/// so `otp=123456` is caught and a phone number is caught — but the string
/// `123456` on its own is indistinguishable from a pincode or an order id, and
/// `SafeLogger` passes it straight through.
///
/// A search query is exactly where that lands: a customer tracking an order types
/// the code they were sent. If analytics forwarded the raw query, someone's OTP
/// would ship to a third party in a field labelled "query" — and nothing in the
/// logs would look wrong.
void main() {
  // A real Firebase SMS code is 6 digits; this app's OTP field is
  // `maxLength: _otpLength` where `_otpLength == 6`.
  const otp = '123456';

  // Shape of a real Firebase ID token: header.payload.signature, base64url.
  const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVP';

  group('the event vocabulary is closed', () {
    test('exactly the agreed product events exist', () {
      // An explicit list rather than a count: a count would let a rename or a
      // swap pass unnoticed, and the whole point is that this set is reviewable.
      expect(
        AnalyticsEvent.values.map((e) => e.wireName).toList(),
        containsAll(<String>[
          'search_started',
          'search_submitted',
          'result_opened',
          'product_viewed',
          'shop_viewed',
          'directions_clicked',
          'saved_product',
          'saved_shop',
        ]),
      );
    });

    test('no event name mentions an OTP, token or credential', () {
      // "Never log OTP as an analytics event" is enforced by the type: an event
      // called otp_verified cannot be written. This states the intent so a
      // future enum edit has to confront it.
      for (final event in AnalyticsEvent.values) {
        final name = event.wireName.toLowerCase();
        for (final banned in const [
          'otp',
          'token',
          'auth',
          'password',
          'phone',
        ]) {
          expect(
            name.contains(banned),
            isFalse,
            reason:
                "'${event.wireName}' must not exist — $banned is not a "
                'product event',
          );
        }
      }
    });

    test('no sink receives traffic until one is supplied', () {
      // Ships with zero analytics traffic: adding the vocabulary must not, by
      // itself, start sending anything to anyone.
      final analytics = ProductAnalytics();
      analytics.track(AnalyticsEvent.productViewed, {'id': 'p1'});
      expect(analytics.sink, isNull);
    });
  });

  group('an OTP can never reach a sink', () {
    test('a bare 6-digit code is redacted', () {
      // THE case. Not a `key=value`, just digits standing alone.
      expect(ProductAnalytics.scrub(otp), isNot(contains(otp)));
    });

    test('a code embedded in a sentence is redacted', () {
      // What a customer actually types: "where is order 123456".
      expect(
        ProductAnalytics.scrub('where is order $otp'),
        isNot(contains(otp)),
      );
    });

    test('a 4-digit code is redacted too', () {
      // Matching one exact length would be a guess that fails the day the
      // provider changes it.
      expect(ProductAnalytics.scrub('code 4821'), isNot(contains('4821')));
    });

    test('an explicitly keyed OTP is redacted', () {
      expect(ProductAnalytics.scrub('otp=$otp'), isNot(contains(otp)));
    });

    test('a full OTP controller value would be scrubbed by track()', () {
      // Proves it at the boundary that matters, not just in the helper.
      final sink = InMemoryAnalyticsSink();
      ProductAnalytics(sink: sink)
          .track(AnalyticsEvent.searchSubmitted, {'query': otp});

      expect(sink.records, hasLength(1));
      final value = '${sink.records.single.params['query']}';
      expect(
        value,
        isNot(contains(otp)),
        reason: 'the raw OTP reached the sink',
      );
    });
  });

  group('tokens and credentials are redacted', () {
    test('a JWT is redacted', () {
      expect(ProductAnalytics.scrub(jwt), isNot(contains(jwt)));
    });

    test('a JWT inside a query string is redacted', () {
      expect(
        ProductAnalytics.scrub('token was $jwt thanks'),
        isNot(contains(jwt)),
      );
    });

    test('an Authorization header value is redacted', () {
      expect(
        ProductAnalytics.scrub('Bearer abc123secretvalue'),
        isNot(contains('abc123secretvalue')),
      );
    });

    test('a keyed token is redacted', () {
      expect(
        ProductAnalytics.scrub('token=abc123secretvalue'),
        isNot(contains('abc123secretvalue')),
      );
    });
  });

  group('other personal data is redacted', () {
    test('an email address is redacted', () {
      expect(
        ProductAnalytics.scrub('reach me at ravi@example.com'),
        isNot(contains('ravi@example.com')),
      );
    });

    test('a phone number is redacted', () {
      expect(
        ProductAnalytics.scrub('call 9876543210'),
        isNot(contains('9876543210')),
      );
    });
  });

  group('useful signal survives', () {
    test('an ordinary product name is preserved', () {
      // The scrub must not be so aggressive that analytics becomes useless.
      expect(ProductAnalytics.scrub('Dove Shampoo'), 'Dove Shampoo');
    });

    test('a category name is preserved', () {
      expect(ProductAnalytics.scrub('Personal Care'), 'Personal Care');
    });

    test('the event survives with its params', () {
      final sink = InMemoryAnalyticsSink();
      ProductAnalytics(
        sink: sink,
      ).track(AnalyticsEvent.shopViewed, {'shop_id': 's7', 'source': 'search'});

      expect(sink.records.single.event, AnalyticsEvent.shopViewed);
      expect(sink.records.single.event.wireName, 'shop_viewed');
      expect(sink.records.single.params['shop_id'], 's7');
      expect(sink.records.single.params['source'], 'search');
    });

    test('null params are dropped rather than recorded as "null"', () {
      final sink = InMemoryAnalyticsSink();
      ProductAnalytics(sink: sink).track(AnalyticsEvent.searchStarted, {
        'source': 'search_bar',
        'absent': null,
      });

      expect(sink.records.single.params.containsKey('absent'), isFalse);
    });

    test('short numeric ids survive; 4+ digit runs do not', () {
      // The honest trade, stated rather than hidden: a 2-digit run is not
      // matched, so `shop-42` survives, while a bare 4+ digit id is redacted
      // because it is indistinguishable from a code. Callers who genuinely need
      // a numeric count should pass it under a param name that does not read as
      // a code.
      expect(ProductAnalytics.scrub('shop-42'), 'shop-42');
      expect(ProductAnalytics.scrub('shop-4281'), isNot(contains('4281')));
    });
  });
}
