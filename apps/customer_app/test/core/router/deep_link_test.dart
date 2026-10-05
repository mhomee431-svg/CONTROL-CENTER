import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/router/deep_link.dart';

void main() {
  group('parseDeepLink', () {
    test('parses an app-relative product path', () {
      expect(
        parseDeepLink('/product/abc123'),
        const DeepLinkIntent(entity: DeepLinkEntity.product, id: 'abc123'),
      );
    });

    test('parses a custom-scheme link', () {
      expect(
        parseDeepLink('passly://product/abc123'),
        const DeepLinkIntent(entity: DeepLinkEntity.product, id: 'abc123'),
      );
    });

    test('parses a custom-scheme link for every entity', () {
      // The entity is the URI *authority* here, not the first path segment.
      // A parser that only reads the path gets the id where it expects the
      // entity and returns null for every one of these.
      expect(
        parseDeepLink('passly://shop/s1'),
        const DeepLinkIntent(entity: DeepLinkEntity.shop, id: 's1'),
      );
      expect(
        parseDeepLink('passly://offer/o1'),
        const DeepLinkIntent(entity: DeepLinkEntity.offer, id: 'o1'),
      );
      expect(
        parseDeepLink('passly://notifications'),
        const DeepLinkIntent.notifications(),
      );
      expect(
        parseDeepLink('passly://search/dove'),
        const DeepLinkIntent.search('dove'),
      );
    });

    test('a custom-scheme link with no id is refused', () {
      expect(parseDeepLink('passly://product'), isNull);
    });

    test('an unknown custom-scheme authority is refused', () {
      expect(parseDeepLink('passly://wallet/abc'), isNull);
    });

    test('parses an https link', () {
      expect(
        parseDeepLink('https://passly.app/shop/shop_9'),
        const DeepLinkIntent(entity: DeepLinkEntity.shop, id: 'shop_9'),
      );
    });

    test('parses a bare entity path with no leading slash', () {
      expect(
        parseDeepLink('offer/deal_1'),
        const DeepLinkIntent(entity: DeepLinkEntity.offer, id: 'deal_1'),
      );
    });

    test('parses a search link from the query string', () {
      expect(
        parseDeepLink('/search?q=dove'),
        const DeepLinkIntent.search('dove'),
      );
    });

    test('parses a search link from the path', () {
      expect(
        parseDeepLink('/search/dove'),
        const DeepLinkIntent.search('dove'),
      );
    });

    test('decodes percent-encoded search text', () {
      expect(
        parseDeepLink('/search?q=dove%20shampoo'),
        const DeepLinkIntent.search('dove shampoo'),
      );
    });

    test('parses the notification inbox with no id', () {
      expect(
        parseDeepLink('/notifications'),
        const DeepLinkIntent.notifications(),
      );
    });

    test('returns null for an unknown entity', () {
      expect(parseDeepLink('/wallet/abc'), isNull);
    });

    test('returns null for an entity with no id', () {
      expect(parseDeepLink('/product'), isNull);
      expect(parseDeepLink('/product/'), isNull);
    });

    test('returns null for null, empty and whitespace input', () {
      expect(parseDeepLink(null), isNull);
      expect(parseDeepLink(''), isNull);
      expect(parseDeepLink('   '), isNull);
    });
    test('returns null for a search link with no query', () {
      expect(parseDeepLink('/search'), isNull);
      expect(parseDeepLink('/search?q='), isNull);
    });

    test('rejects an id longer than the limit', () {
      expect(parseDeepLink('/product/${'a' * 200}'), isNull);
    });

    test('rejects a search query longer than the limit', () {
      expect(parseDeepLink('/search?q=${'a' * 200}'), isNull);
    });

    test('a decoded path-traversal id is caught by the well-formed check', () {
      // `%2F` survives segment splitting and decodes to a real "/", so the id
      // arrives as "../../etc". Parsing cannot reject it -- the parser's job is
      // to understand shapes, not to judge content. The safety boundary is
      // `isWellFormed` / `deepLinkPathFor`, and that is what must refuse to
      // build a route out of it.
      final intent = parseDeepLink('/product/..%2F..%2Fetc');
      expect(intent, isNotNull);
      expect(intent!.isWellFormed, isFalse);
      expect(deepLinkPathFor(intent), isNull);
    });

    test('accepts the common synonyms for each entity', () {
      expect(parseDeepLink('/products/p1')?.entity, DeepLinkEntity.product);
      expect(parseDeepLink('/shops/s1')?.entity, DeepLinkEntity.shop);
      expect(parseDeepLink('/store/s1')?.entity, DeepLinkEntity.shop);
      expect(parseDeepLink('/offers/o1')?.entity, DeepLinkEntity.offer);
      expect(parseDeepLink('/promo/o1')?.entity, DeepLinkEntity.offer);
      expect(
        parseDeepLink('/notification')?.entity,
        DeepLinkEntity.notification,
      );
    });
  });

  group('deepLinkPathFor', () {
    test('builds a path for every supported entity', () {
      expect(
        deepLinkPathFor(
          const DeepLinkIntent(entity: DeepLinkEntity.product, id: 'p1'),
        ),
        '/product/p1',
      );
      expect(
        deepLinkPathFor(
          const DeepLinkIntent(entity: DeepLinkEntity.shop, id: 's1'),
        ),
        '/shop/s1',
      );
      expect(
        deepLinkPathFor(
          const DeepLinkIntent(entity: DeepLinkEntity.offer, id: 'o1'),
        ),
        '/offer/o1',
      );
      expect(
        deepLinkPathFor(const DeepLinkIntent.notifications()),
        '/notifications',
      );
    });

    test('percent-encodes a search query containing an ampersand', () {
      // Without encoding, '/search?q=a&b' would truncate at the '&' and send
      // the customer to results for "a" instead of "a&b".
      final path = deepLinkPathFor(const DeepLinkIntent.search('a&b'));
      expect(path, '/search?q=a%26b');
      expect(Uri.parse(path!).queryParameters['q'], 'a&b');
    });

    test('round-trips a search link through parse and build', () {
      const original = '/search?q=dove%20shampoo';
      final intent = parseDeepLink(original);
      expect(intent, isNotNull);
      final rebuilt = deepLinkPathFor(intent!);
      expect(Uri.parse(rebuilt!).queryParameters['q'], 'dove shampoo');
    });

    test('returns null for a malformed intent rather than a broken path', () {
      expect(
        deepLinkPathFor(const DeepLinkIntent(entity: DeepLinkEntity.product)),
        isNull,
      );
      expect(deepLinkPathFor(const DeepLinkIntent.search('  ')), isNull);
    });

    test('refuses an id containing a path separator', () {
      const intent = DeepLinkIntent(
        entity: DeepLinkEntity.shop,
        id: '../secret',
      );
      expect(deepLinkPathFor(intent), isNull);
    });
  });

  group('DeepLinkIntent equality', () {
    test('identical intents compare equal', () {
      expect(
        const DeepLinkIntent(entity: DeepLinkEntity.product, id: 'p1'),
        const DeepLinkIntent(entity: DeepLinkEntity.product, id: 'p1'),
      );
    });

    test('different ids are not equal', () {
      expect(
        const DeepLinkIntent(entity: DeepLinkEntity.product, id: 'p1'),
        isNot(const DeepLinkIntent(entity: DeepLinkEntity.product, id: 'p2')),
      );
    });
  });
}
