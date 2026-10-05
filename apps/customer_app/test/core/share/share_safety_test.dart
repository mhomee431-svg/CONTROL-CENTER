import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/share/share_safety.dart';

void main() {
  group('findShareLeaks: credentials are always caught', () {
    test('catches a JWT', () {
      const jwt =
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.dBjftJeZ4CVPmB92K27uhbUJU1p1r';
      expect(
        findShareLeaks('Failed for $jwt').map((l) => l.kind),
        contains('jwt'),
      );
    });

    test('catches a Bearer header', () {
      expect(
        findShareLeaks('Authorization: Bearer abc123def456ghi')
            .map((l) => l.kind),
        contains('bearer'),
      );
    });

    test('catches a token assigned in text', () {
      for (final sample in [
        'access_token=abc123def456',
        'refresh-token: abc123def456',
        'api_key = zzz999yyy888',
        'sessionId: 0123456789abcdef',
      ]) {
        expect(
          findShareLeaks(sample),
          isNotEmpty,
          reason: 'must catch: $sample',
        );
      }
    });

    test('catches a secret in a query string', () {
      expect(findShareLeaks('https://passly.app/x?token=abc123'), isNotEmpty);
    });

    test('catches a long hex blob', () {
      expect(
        findShareLeaks('ref 0123456789abcdef0123456789abcdef'),
        isNotEmpty,
      );
    });
  });

  group('findShareLeaks: internal infrastructure is caught', () {
    test('catches a private host in a link', () {
      for (final host in [
        'http://10.0.2.2:8000/product/1',
        'http://localhost:8000/shop/1',
        'http://192.168.1.10/api',
        'http://172.16.4.2/internal',
      ]) {
        expect(
          findShareLeaks(host).map((l) => l.kind),
          contains('private-host'),
          reason: 'must catch: $host',
        );
      }
    });
  });

  group('findShareLeaks: ordinary share copy is NOT flagged', () {
    // A scanner that flags real product copy gets switched off, and a
    // switched-off scanner is worse than none.
    test('accepts realistic product and shop messages', () {
      const samples = [
        'Check out Dove Shampoo (250ml) — ₹249 (MRP ₹299) · 15% OFF at '
            'Sharma Stores (1.2 km) · Unilever — find it near you on Hyperlocal!',
        'Check out Fresh Mart on Hyperlocal!\nMG Road, Indore\n'
            'Rating: 4.5 (128 reviews)\n3 active offers\nGrocery · Supermarket',
        '₹1,299 · 20% OFF · 4.8 stars · 2,304 reviews',
      ];
      for (final sample in samples) {
        expect(
          findShareLeaks(sample),
          isEmpty,
          reason: 'false positive on real copy: $sample',
        );
      }
    });

    test('accepts short numeric ids that are not secrets', () {
      expect(findShareLeaks('Order 48291 · Shop 12'), isEmpty);
    });

    test('handles null and empty input', () {
      expect(findShareLeaks(null), isEmpty);
      expect(findShareLeaks(''), isEmpty);
    });
  });

  group('ShareLeak excerpt', () {
    test('is truncated so it is safe to log', () {
      final leak = findShareLeaks('Bearer abcdefghijklmnopqrstuvwxyz0123456789')
          .first;
      expect(leak.excerpt.length, lessThanOrEqualTo(13));
    });

    test('toString does not print the leaked value', () {
      const leak = ShareLeak('jwt', 'eyJhbGciOiJIUzI1NiJ9');
      expect(leak.toString(), 'ShareLeak(jwt)');
      expect(leak.toString(), isNot(contains('eyJ')));
    });
  });
}
