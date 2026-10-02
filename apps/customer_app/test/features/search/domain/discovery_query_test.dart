import 'dart:io';

import 'package:hyperlocal_app/features/search/domain/discovery_query.dart';
import 'package:hyperlocal_app/features/search/domain/models/search_models.dart';
import 'package:hyperlocal_app/features/search/domain/semantic_reranker.dart';
import 'package:flutter_test/flutter_test.dart';

/// A representative EAN-13 with a correct GS1 check digit.
const String kValidEan13 = '8901030891236';

const DiscoveryLexicon kLexicon = DiscoveryLexicon(
  brands: {'dove', 'amul', 'colgate'},
  categories: {'beauty & personal care', 'household goods'},
);

DiscoveryQuery classify(String raw) =>
    classifyDiscovery(raw, lexicon: kLexicon);

void main() {
  group('discovery covers the five required kinds of query', () {
    test('exact product name', () {
      final q = classify('Dove Beauty Bar');
      expect(q.mode, DiscoveryMode.productName);
      expect(q.normalized, 'Dove Beauty Bar');
    });

    test('brand, on its own', () {
      final q = classify('Dove');
      expect(q.mode, DiscoveryMode.brand);
      expect(q.confidence, DiscoveryConfidence.certain);
    });

    test('brand, mentioned inside a longer query', () {
      final q = classify('Dove shampoo');
      expect(q.mode, DiscoveryMode.brand);
      // Not "certain": the trailing word may be the real product name.
      expect(q.confidence, DiscoveryConfidence.likely);
    });

    test('variant, identified by its size token', () {
      expect(classify('Dove 250ml').mode, DiscoveryMode.variant);
      expect(classify('Amul 500g').mode, DiscoveryMode.variant);
      expect(classify('Colgate 2x').mode, DiscoveryMode.variant);
    });

    test('category', () {
      final q = classify('Household Goods');
      expect(q.mode, DiscoveryMode.category);
      expect(q.confidence, DiscoveryConfidence.certain);
    });

    test('barcode', () {
      final q = classify(kValidEan13);
      expect(q.mode, DiscoveryMode.barcode);
      expect(q.confidence, DiscoveryConfidence.certain);
      expect(q.requiresBarcodeLookup, isTrue);
    });
  });

  group('barcode routing — the behaviour that was previously missing', () {
    test('a typed barcode must reach the barcode route, not text search', () {
      // The regression this guards: a barcode is a 13-character string, so
      // with no vocabulary it was sent to the full-text index, which cannot
      // match it. requiresBarcodeLookup is what routes it.
      expect(classify(kValidEan13).requiresBarcodeLookup, isTrue);
    });

    test('separators printed on packaging are tolerated', () {
      final q = classify('8901030 891236');
      expect(q.mode, DiscoveryMode.barcode);
      expect(q.normalized, kValidEan13);
    });

    test('a bad check digit still routes to the barcode lookup', () {
      // A mistyped barcode should produce an honest "not found" from the exact
      // route, not a near-empty text search that looks like a broken search.
      final q = classify('8901030891237');
      expect(q.mode, DiscoveryMode.barcode);
      expect(q.confidence, DiscoveryConfidence.guess);
      expect(q.requiresBarcodeLookup, isTrue);
    });

    test('digits of a non-barcode length are not treated as a barcode', () {
      expect(classify('12345').mode, isNot(DiscoveryMode.barcode));
    });
  });

  group('explicit prefixes win over every heuristic', () {
    test('each prefix forces its mode', () {
      expect(classify('brand:unknownbrand').mode, DiscoveryMode.brand);
      expect(classify('variant:Dove 250ml').mode, DiscoveryMode.variant);
      expect(classify('barcode:$kValidEan13').mode, DiscoveryMode.barcode);
    });

    test('a prefix strips itself from the normalized query', () {
      // The prefix is syntax for the customer, not part of the search term.
      expect(classify('brand:Dove').normalized, 'Dove');
    });

    test('an explicit barcode prefix forces routing even if malformed', () {
      final q = classify('barcode:12');
      expect(q.requiresBarcodeLookup, isTrue);
      expect(q.confidence, DiscoveryConfidence.certain);
    });
  });

  group('core discovery does not depend on AI', () {
    test('the classifier module imports nothing but its own domain', () {
      final source = File('lib/features/search/domain/discovery_query.dart')
          .readAsStringSync();

      final imports = RegExp(
        r"^import\s+'([^']+)'",
        multiLine: true,
      ).allMatches(source).map((m) => m.group(1)!).toList();

      // Exactly one import: the barcode validator it reuses. No riverpod, no
      // models, no http, and above all no reference to the semantic layer.
      expect(imports, ['barcode_validation.dart']);
    });

    test('the classifier code never references a reranker or a model', () {
      final source = File('lib/features/search/domain/discovery_query.dart')
          .readAsStringSync();

      // Comments are excluded on purpose: the file documents *why* semantic
      // search is separate, and that prose naming the other library is
      // documentation, not a dependency. Only executable lines matter here.
      final code = source
          .split('\n')
          .where((l) {
            final t = l.trimLeft();
            return !t.startsWith('//') && !t.startsWith('///');
          })
          .join('\n');

      for (final forbidden in const [
        'SemanticReranker',
        'semantic_reranker',
        'embedding',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason: 'core discovery code must not reference "$forbidden"',
        );
      }
    });

    test('the reason the brand/variant split exists is pinned', () {
      // "Dove Beauty Bar" is a product description, so narrowing it to the brand
      // would return Dove Cream as well - a worse answer than plain text search.
      expect(classify('Dove Beauty Bar').mode, DiscoveryMode.productName);
      // "Dove shampoo" is brand-scoping: one qualifier word, so the brand wins.
      expect(classify('Dove shampoo').mode, DiscoveryMode.brand);
      // A size token outranks a brand mention, because it narrows instead of
      // widening: "Dove 250ml" means that one bottle.
      expect(classify('Dove 250ml').mode, DiscoveryMode.variant);
    });

    test('the classifier is a pure function of its input', () {
      expect(classify('Dove 250ml'), classify('Dove 250ml'));
    });
  });

  group('unicode is preserved, not stripped', () {
    test('an accented, apostrophised name is a product name verbatim', () {
      final q = classify("L'Oréal Café");
      expect(q.mode, DiscoveryMode.productName);
      // The earlier ASCII-only input formatter would have mangled this to
      // "LOral Caf"; discovery must see exactly what the customer typed.
      expect(q.normalized, "L'Oréal Café");
    });

    test('a non-Latin script is left intact', () {
      expect(classify('चीनी').normalized, 'चीनी');
    });
  });

  group('semantic layer is additive and cannot degrade search', () {
    final results = [
      _product('1', 'Dove Bar'),
      _product('2', 'Dove Soap'),
      _product('3', 'Dove Cream'),
    ];

    test('the default is a real no-op that preserves order', () async {
      const pipeline = ProductDiscoveryPipeline(NoopSemanticReranker());
      expect(pipeline.isSemanticActive, isFalse);
      final out = await pipeline.run('dove', results);
      expect(out.map((e) => e.id), ['1', '2', '3']);
    });

    test('a reorder is applied when it is a true permutation', () async {
      final pipeline = ProductDiscoveryPipeline(_ReversingReranker());
      final out = await pipeline.run('dove', results);
      expect(pipeline.isSemanticActive, isTrue);
      expect(out.map((e) => e.id), ['3', '2', '1']);
    });

    test('a reranker that DROPS a product is ignored, not obeyed', () async {
      // The contract that keeps "AI is optional" honest: a model that filters
      // rather than reorders would otherwise silently hide real stock.
      final pipeline = ProductDiscoveryPipeline(_DroppingReranker());
      final out = await pipeline.run('dove', results);
      expect(out.map((e) => e.id), ['1', '2', '3']);
    });

    test('a reranker that INVENTS a product is ignored', () async {
      final pipeline = ProductDiscoveryPipeline(_InventingReranker());
      final out = await pipeline.run('dove', results);
      expect(out.map((e) => e.id), ['1', '2', '3']);
    });

    test('a throwing reranker falls back to the core ranking', () async {
      final pipeline = ProductDiscoveryPipeline(_ThrowingReranker());
      final out = await pipeline.run('dove', results);
      expect(out.map((e) => e.id), ['1', '2', '3']);
    });

    test('a single result skips the stage entirely', () async {
      final pipeline = ProductDiscoveryPipeline(_ReversingReranker());
      final out = await pipeline.run('dove', [results.first]);
      expect(out.single.id, '1');
    });
  });
}

ShopProductResult _product(String id, String name) => ShopProductResult(
  id: id,
  productId: 'p$id',
  productName: name,
  productImageUrl: '',
  shopId: 's$id',
  shopName: 'Shop',
  price: 10,
  isAvailable: true,
  distanceInKm: 1,
  shopRating: 4,
  lastUpdated: DateTime.fromMillisecondsSinceEpoch(0),
);

class _ReversingReranker implements SemanticReranker {
  @override
  Future<List<ShopProductResult>> reorder(
    String query,
    List<ShopProductResult> results,
  ) async => results.reversed.toList();
}

/// Violates the contract by removing a product.
class _DroppingReranker implements SemanticReranker {
  @override
  Future<List<ShopProductResult>> reorder(
    String query,
    List<ShopProductResult> results,
  ) async => results.take(2).toList();
}

/// Violates the contract by adding a product.
class _InventingReranker implements SemanticReranker {
  @override
  Future<List<ShopProductResult>> reorder(
    String query,
    List<ShopProductResult> results,
  ) async => [...results, _product('99', 'Injected')];
}

class _ThrowingReranker implements SemanticReranker {
  @override
  Future<List<ShopProductResult>> reorder(
    String query,
    List<ShopProductResult> results,
  ) async => throw Exception('model unavailable');
}
