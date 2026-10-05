import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/features/search/data/discovery_lexicon_provider.dart';
import 'package:hyperlocal_app/features/search/domain/discovery_query.dart';
import 'package:hyperlocal_app/features/search/domain/models/search_models.dart';
import 'package:hyperlocal_app/features/search/domain/search_repository.dart';
import 'package:hyperlocal_app/features/search/domain/semantic_reranker.dart';
import 'package:hyperlocal_app/features/search/presentation/controllers/search_controller.dart';

/// A real EAN-13 (correct GS1 check digit).
const String kTypedBarcode = '8901030891236';

/// Records which route each call took, so a test can assert the controller
/// asked the RIGHT endpoint rather than merely that something was fetched.
class _RecordingRepository implements SearchRepository {
  final List<String> textQueries = [];
  final List<({String code, int page})> barcodeLookups = [];

  /// The filters the controller actually sent on its most recent text search.
  Map<String, dynamic>? lastFilters;

  @override
  Future<List<ShopProductResult>> searchProducts({
    required String query,
    required int page,
    required int limit,
    SortOption sort = SortOption.nearest,
    Map<String, dynamic>? filters,
    double? latitude,
    double? longitude,
  }) async {
    textQueries.add(query);
    lastFilters = filters;
    return _rows('text', limit);
  }

  @override
  Future<List<ShopProductResult>> lookupBarcode(
    String barcode, {
    double? latitude,
    double? longitude,
    int page = 1,
    int limit = 20,
  }) async {
    barcodeLookups.add((code: barcode, page: page));
    return _rows('barcode', limit);
  }

  List<ShopProductResult> _rows(String label, int limit) => List.generate(
    limit,
    (i) => ShopProductResult(
      id: '$label-$i',
      productId: 'p_$label$i',
      productName: '$label row $i',
      productImageUrl: '',
      shopId: 's$i',
      shopName: 'Shop $i',
      price: 10.0 + i,
      isAvailable: true,
      distanceInKm: 1,
      shopRating: 4,
      lastUpdated: DateTime(2026, 1, 1),
    ),
  );

  @override
  Future<List<String>> getPopularSearches() async => const [];

  @override
  Future<List<String>> getRecentSearches() async => const [];

  @override
  Future<List<SearchSuggestion>> getSuggestions(String query) async => const [];
}

ProviderContainer _boot(
  _RecordingRepository repo, {
  Set<String> brands = const {},
  Set<String> categories = const {},
}) {
  final container = ProviderContainer(
    overrides: [searchRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  // Seed the warmed caches directly. The lexicon is a pure synchronous read, so
  // this is the only way a test supplies vocabulary -- and it also proves the
  // point: nothing here touches the network.
  if (brands.isNotEmpty) {
    container.read(brandVocabularyProvider.notifier).seed(brands);
  }
  if (categories.isNotEmpty) {
    container.read(categoryVocabularyProvider.notifier).seed(categories);
  }
  return container;
}

void main() {
  group('a typed barcode reaches the barcode route', () {
    test('and the text search is never called for it', () async {
      final repo = _RecordingRepository();
      final container = _boot(repo);

      container.read(searchResultsProvider(kTypedBarcode));
      await Future<void>.delayed(Duration.zero);

      expect(repo.barcodeLookups.map((e) => e.code), [
        kTypedBarcode,
      ], reason: 'the exact identifier route is the whole point');
      expect(
        repo.textQueries,
        isEmpty,
        reason:
            'a text search for 13 digits cannot match, which is the bug this '
            'routing fixes',
      );
    });

    test('the separators printed on packaging are stripped first', () async {
      final repo = _RecordingRepository();
      final container = _boot(repo);

      container.read(searchResultsProvider('8901030 891236'));
      await Future<void>.delayed(Duration.zero);

      expect(repo.barcodeLookups.single.code, kTypedBarcode);
    });

    test('and its later pages stay on the barcode route', () async {
      // A product stocked by many nearby shops pages just like any other list,
      // so page 2 must not silently switch back to full-text search.
      final repo = _RecordingRepository();
      final container = _boot(repo);

      container.read(searchResultsProvider(kTypedBarcode));
      await Future<void>.delayed(Duration.zero);

      await container
          .read(searchResultsProvider(kTypedBarcode).notifier)
          .fetchNextPage();

      expect(repo.barcodeLookups.map((e) => e.page), [1, 2]);
      expect(repo.textQueries, isEmpty);
    });
  });

  group('everything else still uses the text search', () {
    test('a plain product name', () async {
      final repo = _RecordingRepository();
      final container = _boot(repo);

      container.read(searchResultsProvider('Dove Beauty Bar'));
      await Future<void>.delayed(Duration.zero);

      expect(repo.textQueries, ['Dove Beauty Bar']);
      expect(repo.barcodeLookups, isEmpty);
    });

    test('a barcode-shaped string of the wrong length', () async {
      final repo = _RecordingRepository();
      final container = _boot(repo);

      container.read(searchResultsProvider('12345'));
      await Future<void>.delayed(Duration.zero);

      expect(repo.textQueries, ['12345']);
      expect(repo.barcodeLookups, isEmpty);
    });

    test('a category name', () async {
      final repo = _RecordingRepository();
      final container = _boot(repo);

      container.read(searchResultsProvider('Household Goods'));
      await Future<void>.delayed(Duration.zero);

      expect(repo.textQueries, ['Household Goods']);
      expect(repo.barcodeLookups, isEmpty);
    });
  });

  group('the optional semantic layer is genuinely wired, not aspirational', () {
    test('overriding the reranker changes the order the customer sees', () async {
      // If the controller never called the pipeline, overriding the provider
      // would silently do nothing and the "AI is optional" seam would be a lie.
      final plain = _RecordingRepository();
      final plainContainer = _boot(plain);
      plainContainer.read(searchResultsProvider('dove'));
      await Future<void>.delayed(Duration.zero);
      final baseline = plainContainer
          .read(searchResultsProvider('dove'))
          .results
          .map((r) => r.id)
          .toList();

      final reranked = _RecordingRepository();
      final container = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(reranked),
          semanticRerankerProvider.overrideWithValue(_ReversingReranker()),
        ],
      );
      addTearDown(container.dispose);
      container.read(searchResultsProvider('dove'));
      await Future<void>.delayed(Duration.zero);

      final reordered = container
          .read(searchResultsProvider('dove'))
          .results
          .map((r) => r.id)
          .toList();

      expect(reordered, baseline.reversed.toList());
    });

    test('a reranker that drops rows cannot shrink the result list', () async {
      // The guarantee that makes the layer safe to enable: it may reorder, it
      // may never hide stock the core search found.
      final withDropper = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(_RecordingRepository()),
          semanticRerankerProvider.overrideWithValue(_DroppingReranker()),
        ],
      );
      addTearDown(withDropper.dispose);

      withDropper.read(searchResultsProvider('dove'));
      await Future<void>.delayed(Duration.zero);

      expect(
        withDropper.read(searchResultsProvider('dove')).results,
        isNotEmpty,
        reason: 'a filtering model must not be able to empty a good search',
      );
    });
  });

  group('the lexicon is driven by the backend, not a hardcoded list', () {
    test('a published category classifies as a category', () {
      final container = _boot(
        _RecordingRepository(),
        categories: const {'household goods'},
      );

      expect(
        container.read(discoveryIntentProvider('Household Goods')).mode,
        DiscoveryMode.category,
      );
    });

    test('a category published TODAY is recognised with no app release', () {
      // The regression this guards. The category vocabulary used to be
      // `ApprovedCategories.names`, a compiled-in list, so a brand-new category
      // would be shown on the home screen and then silently lose its category
      // filter on tap, degrading to a text search for its own name.
      final container = _boot(
        _RecordingRepository(),
        categories: const {'pet supplies'},
      );

      expect(
        container.read(discoveryIntentProvider('Pet Supplies')).mode,
        DiscoveryMode.category,
        reason: 'the vocabulary comes from the catalogue, so new names work',
      );
    });

    test('a known brand activates as soon as the catalogue supplies it', () async {
      // Before the catalogue read lands (or if it fails) the lexicon simply has
      // no brands, so "Dove" is a product-name search -- which still returns
      // Dove's products, because the text index knows the brand. Discovery
      // degrades, it does not break.
      final container = _boot(_RecordingRepository());
      expect(
        container.read(discoveryIntentProvider('Dove')).mode,
        DiscoveryMode.productName,
        reason: 'no hardcoded brand list ships in the app; it would rot',
      );

      final withBrands = _boot(_RecordingRepository(), brands: const {'dove'});
      expect(
        withBrands.read(discoveryIntentProvider('Dove')).mode,
        DiscoveryMode.brand,
      );
    });
  });

  group('a certain brand or category verdict reaches the backend filter', () {
    // The backend accepts `brand`/`category` as "ID or name", and the
    // repository already forwarded them -- but until the classifier's verdict
    // is merged into the filters they are always absent, so a brand query only
    // ever reached the free-text index.
    test('a bare brand is sent as a brand filter', () async {
      final repo = _RecordingRepository();
      final container = _boot(repo, brands: const {'dove'});

      container.read(searchResultsProvider('Dove'));
      await Future<void>.delayed(Duration.zero);

      expect(repo.lastFilters?['brand'], 'Dove');
    });

    test('a category is sent as a category filter', () async {
      final repo = _RecordingRepository();
      final container = _boot(repo, categories: const {'household goods'});

      container.read(searchResultsProvider('Household Goods'));
      await Future<void>.delayed(Duration.zero);

      expect(repo.lastFilters?['category'], 'Household Goods');
    });

    test('a brand-new category still gets a real category filter', () async {
      // The end-to-end payoff of the backend-driven vocabulary: a category the
      // platform published today is browsed by filter, not by searching for its
      // own name.
      final repo = _RecordingRepository();
      final container = _boot(repo, categories: const {'pet supplies'});

      container.read(searchResultsProvider('Pet Supplies'));
      await Future<void>.delayed(Duration.zero);

      expect(repo.lastFilters?['category'], 'Pet Supplies');
    });

    test('a plain product name narrows nothing', () async {
      final repo = _RecordingRepository();
      final container = _boot(repo, brands: const {'dove'});

      container.read(searchResultsProvider('Shampoo'));
      await Future<void>.delayed(Duration.zero);

      expect(repo.lastFilters?['brand'], isNull);
      expect(repo.lastFilters?['category'], isNull);
    });

    test('a LOW-confidence brand match does NOT narrow', () async {
      // "Dove shampoo" is a likely brand match. Filtering on it would exclude
      // products the text search would have found, and a wrong narrow filter
      // HIDES real stock -- so only a certain verdict may narrow.
      final repo = _RecordingRepository();
      final container = _boot(repo, brands: const {'dove'});

      container.read(searchResultsProvider('Dove shampoo'));
      await Future<void>.delayed(Duration.zero);

      expect(repo.lastFilters?['brand'], isNull);
    });

    test("the customer's own filters are never overwritten", () async {
      final repo = _RecordingRepository();
      final container = _boot(repo, brands: const {'dove'});

      container.read(searchResultsProvider('Dove'));
      await Future<void>.delayed(Duration.zero);
      container.read(searchResultsProvider('Dove').notifier).updateFilters({
        'in_stock': true,
        'brand': 'Explicit Choice',
      });
      await Future<void>.delayed(Duration.zero);

      expect(
        repo.lastFilters?['brand'],
        'Explicit Choice',
        reason: 'a deliberate customer choice outranks an inferred guess',
      );
      expect(repo.lastFilters?['in_stock'], isTrue);
    });
  });

  // The vocabulary is warmed by a startup side effect that RACES the first
  // search, so "seeded before anything read it" is not the only ordering that
  // can happen -- it is merely the one a test can write down most easily. Held
  // as a mutable field inside a plain `Provider`, the lexicon would cache the
  // empty vocabulary captured at that first read for the REST OF THE SESSION,
  // and the warm-up succeeding later would change nothing. No error, no log;
  // categories and brands simply stop being recognised. These tests pin the
  // rebuild, which is why the vocabularies are Notifiers and not mutable
  // objects.
  group('a vocabulary arriving AFTER the first read still takes effect', () {
    test('a category searched during the race is filtered once warmed', () async {
      final repo = _RecordingRepository();
      final container = _boot(repo); // no vocabulary yet

      container.read(searchResultsProvider('Beauty & Personal Care'));
      await Future<void>.delayed(Duration.zero);
      expect(
        repo.lastFilters?['category'],
        isNull,
        reason: 'nothing is known yet, so the query must not narrow',
      );

      // The warm-up lands late — the slow-connection case.
      container.read(categoryVocabularyProvider.notifier).seed(const {
        'beauty & personal care',
      });

      container.invalidate(searchResultsProvider('Beauty & Personal Care'));
      container.read(searchResultsProvider('Beauty & Personal Care'));
      await Future<void>.delayed(Duration.zero);

      expect(
        repo.lastFilters?['category'],
        'Beauty & Personal Care',
        reason:
            'a vocabulary that arrives late must still be used; a lexicon that '
            'latched the empty first read would fail exactly here',
      );
    });

    test('the same holds for a brand', () async {
      final repo = _RecordingRepository();
      final container = _boot(repo);

      container.read(searchResultsProvider('Dove'));
      await Future<void>.delayed(Duration.zero);
      expect(repo.lastFilters?['brand'], isNull);

      container.read(brandVocabularyProvider.notifier).seed(const {'dove'});

      container.invalidate(searchResultsProvider('Dove'));
      container.read(searchResultsProvider('Dove'));
      await Future<void>.delayed(Duration.zero);

      expect(repo.lastFilters?['brand'], 'Dove');
    });
  });
}

/// Reverses the list: a legal permutation, so the pipeline must apply it.
class _ReversingReranker implements SemanticReranker {
  @override
  Future<List<ShopProductResult>> reorder(
    String query,
    List<ShopProductResult> results,
  ) async => results.reversed.toList();
}

/// Violates the contract by dropping rows, so the pipeline must ignore it.
class _DroppingReranker implements SemanticReranker {
  @override
  Future<List<ShopProductResult>> reorder(
    String query,
    List<ShopProductResult> results,
  ) async => const [];
}
