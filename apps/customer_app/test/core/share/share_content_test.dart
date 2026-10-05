import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/share/share_content.dart';
import 'package:hyperlocal_app/core/share/share_safety.dart';

void main() {
  group('product share never exposes the internal id in prose', () {
    test('the id appears only in the url, never in the message', () {
      const productId = 'a1b2c3d4-product-internal';
      final content = buildProductShareContent(
        productName: 'Dove Shampoo',
        price: 249,
        productId: productId,
      );
      expect(
        content.message.contains(productId),
        isFalse,
        reason:
            'a database key in shareable prose is an internal identifier '
            'leak',
      );
    });

    test('no composed product share trips the leak scanner', () {
      // The end-to-end guarantee, stated once: whatever the composer produces
      // for realistic input is safe to hand to a third-party app.
      final contents = [
        buildProductShareContent(
          productName: 'Dove Shampoo',
          price: 249,
          mrp: 299,
          discountPercent: 15,
          shopName: 'Sharma Stores',
          distanceInKm: 1.2,
          variant: '250ml',
          brand: 'Unilever',
          productId: 'prod_123',
        ),
        buildProductShareContent(productName: 'A', productId: 'prod_123'),
        buildProductShareContent(productName: ''),
      ];
      for (final content in contents) {
        expect(findShareLeaks(content.message), isEmpty);
        expect(findShareLeaks(content.url), isEmpty);
        expect(findShareLeaks(content.fullText), isEmpty);
      }
    });

    test('a name carrying a credential is refused, not shared', () {
      // Proves the assert gate is live rather than decorative: a backend that
      // somehow returned a token as a product name must not reach a chat.
      expect(
        () => buildProductShareContent(
          productName: 'Sneaky eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.dBjftJeZ4CVPmB92K27uhbUJU1p1r',
        ),
        throwsA(isA<UnsafeShareContentException>()),
      );
    });
  });

  group('shop share never exposes internal detail', () {
    test('does not share raw coordinates', () {
      final content = buildShopShareContent(
        shopName: 'Fresh Mart',
        address: 'MG Road, Indore',
        rating: 4.5,
        reviewCount: 128,
        shopId: 'shop_9',
      );
      expect(content.message, isNot(contains('22.7196')));
      expect(findShareLeaks(content.fullText), isEmpty);
    });

    test('omits the id from the message', () {
      const shopId = 'shop-internal-9';
      final content = buildShopShareContent(
        shopName: 'Fresh Mart',
        shopId: shopId,
      );
      expect(content.message.contains(shopId), isFalse);
    });

    test('renders offers in singular and plural correctly', () {
      expect(
        buildShopShareContent(shopName: 'A', activeOfferCount: 1).message,
        contains('1 active offer'),
      );
      expect(
        buildShopShareContent(shopName: 'A', activeOfferCount: 1).message,
        isNot(contains('1 active offers')),
      );
      expect(
        buildShopShareContent(shopName: 'A', activeOfferCount: 3).message,
        contains('3 active offers'),
      );
    });

    test('omits zero offers rather than saying "0 active offers"', () {
      final content = buildShopShareContent(shopName: 'A', activeOfferCount: 0);
      expect(content.message, isNot(contains('offer')));
    });
  });

  group('share link construction', () {
    test('produces no link when no public origin is configured', () {
      // The default in dev/staging/test. A missing link is a small loss; a
      // leaked internal host is unrecoverable.
      expect(ShareLinkConfig.isEnabled, isFalse);
      final content = buildProductShareContent(
        productName: 'Dove',
        productId: 'prod_1',
      );
      expect(content.url, isNull);
      expect(content.hasLink, isFalse);
      expect(content.fullText, content.message);
    });

    test('rejects a malformed id rather than building a broken link', () {
      final content = buildProductShareContent(
        productName: 'Dove',
        productId: '../etc/passwd',
      );
      expect(content.url, isNull);
      expect(content.message, contains('Dove'));
    });

    test('rejects a blank id', () {
      expect(
        buildProductShareContent(productName: 'Dove', productId: '   ').url,
        isNull,
      );
    });
  });

  group('preferredProductShareId', () {
    test('prefers a public barcode over the internal id', () {
      expect(
        preferredProductShareId(
          productId: 'internal-uuid-ish-id',
          identifiers: [(type: 'EAN', value: '8901030891234')],
        ),
        '8901030891234',
      );
    });

    test('accepts the common barcode type spellings', () {
      for (final type in ['ean', 'EAN', 'upc', 'UPC-A', 'gtin']) {
        expect(
          preferredProductShareId(
            productId: 'internal',
            identifiers: [(type: type, value: '1234567890123')],
          ),
          '1234567890123',
          reason: 'type $type should be treated as public',
        );
      }
    });

    test('ignores a non-public identifier type', () {
      expect(
        preferredProductShareId(
          productId: 'internal',
          identifiers: [(type: 'internal_ref', value: 'abc-123')],
        ),
        'internal',
      );
    });

    test('ignores a barcode that is not route-safe', () {
      expect(
        preferredProductShareId(
          productId: 'internal',
          identifiers: [(type: 'ean', value: '89/0103*0891234')],
        ),
        'internal',
      );
    });

    test('returns null when there is no usable id at all', () {
      expect(preferredProductShareId(productId: ''), isNull);
      expect(preferredProductShareId(productId: 'not/safe'), isNull);
    });
  });

  group('assertShareIsSafe', () {
    test('throws when an id is interpolated into the message', () {
      // The guard throws its own exception rather than a bare AssertionError:
      // `assert` evaluates the closure, and an exception raised inside it
      // propagates unchanged. That is what makes the failure readable in a test
      // report -- the type names the cause instead of saying "assertion failed".
      expect(
        () => assertShareIsSafe(
          const ShareContent(subject: 's', message: 'Product 42 is great'),
          internalIds: const ['42'],
        ),
        throwsA(isA<UnsafeShareContentException>()),
      );
    });

    test('passes a clean share', () {
      assertShareIsSafe(
        const ShareContent(subject: 's', message: 'Dove Shampoo ₹249'),
      );
    });
  });

  group('ShareContent', () {
    test('fullText appends the link on its own line', () {
      const content = ShareContent(
        subject: 's',
        message: 'Dove',
        url: 'https://passly.app/product/1',
      );
      expect(content.fullText, 'Dove\nhttps://passly.app/product/1');
    });

    test('fullText is just the message when there is no link', () {
      const content = ShareContent(subject: 's', message: 'Dove');
      expect(content.hasLink, isFalse);
      expect(content.fullText, 'Dove');
    });
  });
}
