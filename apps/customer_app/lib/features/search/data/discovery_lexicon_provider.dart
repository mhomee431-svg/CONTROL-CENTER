/// The discovery vocabulary the customer app ships with.
///
/// ## WHY THIS IS A SEPARATE FILE
///
/// `discovery_query.dart` holds the classifier and imports nothing but the
/// barcode validator, so the core of discovery cannot reach for the catalogue,
/// the network or a model. This file supplies the *data* the classifier is
/// parameterised by, which is the only part that depends on the app.
///
/// ## BOTH VOCABULARIES COME FROM THE BACKEND
///
/// Neither brand nor category names are compiled into the app. Both are
/// admin-managed data with no upper bound, and a hardcoded copy does not fail
/// loudly -- it just silently misclassifies whatever was added after it was
/// written. That was the original bug behind the category allow-list: a
/// category could be published and still be treated as a product name.
///
/// Both are fetched once at startup (see `main.dart`) into an in-memory
/// vocabulary, and the classifier reads that synchronously. Before the warm-up
/// lands, or if it fails, both are EMPTY and the query falls back to a text
/// search -- which still returns the right products, because the backend's text
/// index matches brand and category text.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../domain/discovery_query.dart';

/// The in-memory category vocabulary, populated once per session.
///
/// Same shape and same rationale as [BrandVocabulary]: the lexicon is read on
/// every keystroke, so it must be a pure synchronous read, and the fetch is an
/// explicit one-shot startup side effect.
///
/// This is what removes the last hardcoded category list from the search path.
/// Previously the classifier recognised a category only because its name was in
/// `ApprovedCategories`, so a category an admin had just published would be
/// shown on the home screen but then silently lose its `category` filter on tap
/// and degrade to a text search for its own name.
///
/// WHY A Notifier AND NOT A MUTABLE OBJECT IN A `Provider`
/// ------------------------------------------------------
/// The state IS the set, so seeding assigns a new set and every watcher
/// rebuilds. Held instead as a mutable field on an object wrapped in a plain
/// `Provider`, the provider's value never changes identity, so
/// [discoveryLexiconProvider] keeps whatever it captured at its FIRST read. Read
/// the lexicon once before the warm-up lands — a search before the fetch
/// returns, which is the normal case on a slow connection — and the whole
/// session is silently stuck with an empty vocabulary even after the fetch
/// succeeds. Nothing throws; categories and brands just stop being recognised.
class CategoryVocabulary extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  /// Replaces the vocabulary with [names], lower-cased and blank-free.
  void seed(Iterable<String> names) => state = _normalizeVocabulary(names);
}

final categoryVocabularyProvider =
    NotifierProvider<CategoryVocabulary, Set<String>>(CategoryVocabulary.new);

/// Fills [categoryVocabularyProvider] from the public category list, once.
final categoryVocabularyWarmupProvider = FutureProvider<void>((ref) async {
  try {
    final data = await ref
        .watch(apiClientProvider)
        .get(ApiEndpoints.categories, requiresAuth: false);
    ref.read(categoryVocabularyProvider.notifier).seed(_parseNames(data));
  } catch (_) {
    // Offline or a 5xx: the vocabulary stays empty and a category query simply
    // falls back to a text search, which still returns the right products.
  }
});

/// The in-memory brand vocabulary, populated once per session.
///
/// THIS IS A CACHE, NOT A FETCH
/// ----------------------------
/// The lexicon is read on every search keystroke, so it must be a pure,
/// synchronous read. An earlier version resolved it through a `FutureProvider`,
/// which meant *searching* triggered a network call — and in the test suite that
/// turned previously hermetic search tests into network calls with a three
/// attempt retry storm. Searching must never depend on a request the customer
/// did not ask for.
///
/// The population side effect is therefore explicit and one-shot:
/// [warmBrandVocabulary] at app start, nothing else.
class BrandVocabulary extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  /// Replaces the vocabulary with [names], lower-cased and blank-free.
  void seed(Iterable<String> names) => state = _normalizeVocabulary(names);
}

final brandVocabularyProvider = NotifierProvider<BrandVocabulary, Set<String>>(
  BrandVocabulary.new,
);

/// Fills [brandVocabularyProvider] from the public brand catalogue, once.
///
/// Called from app startup. Never throws and never retries: a failure simply
/// leaves the vocabulary empty, a brand query degrades to a product-name
/// search, and that still returns the right products because the backend's text
/// index matches brand names. Discovery degrades; it does not break.
final brandVocabularyWarmupProvider = FutureProvider<void>((ref) async {
  try {
    final data = await ref
        .watch(apiClientProvider)
        .get(ApiEndpoints.catalogBrands, requiresAuth: false);
    ref.read(brandVocabularyProvider.notifier).seed(_parseNames(data));
  } catch (_) {
    // Offline, a 5xx, or a shape change: the vocabulary simply stays empty.
  }
});

/// Lower-case and blank-strip a vocabulary, shared by both warm-ups.
///
/// Returns a NEW set on every call, which is what makes `state` change identity
/// and dependents rebuild — see [CategoryVocabulary].
Set<String> _normalizeVocabulary(Iterable<String> names) => {
  for (final n in names)
    if (n.trim().isNotEmpty) n.trim().toLowerCase(),
};

/// Lower-cased `name` values from a list payload.
///
/// Tolerant by design: the backend wraps rows in the standard success envelope,
/// but a bare list is accepted too, and a row that cannot yield a name is
/// skipped rather than failing the whole vocabulary. Shared by the brand and
/// category warm-ups, which are the same shape.
Set<String> _parseNames(Object? data) {
  Object? rows = data;
  if (rows is Map) {
    // The backend wraps rows in the standard success envelope; a bare list is
    // accepted too, so neither shape is assumed.
    rows = rows['data'] ?? rows['results'];
  }
  if (rows is! List) return const <String>{};

  final out = <String>{};
  for (final row in rows) {
    if (row is! Map) continue;
    final name = row['name'];
    if (name is! String) continue;
    final trimmed = name.trim().toLowerCase();
    if (trimmed.isNotEmpty) out.add(trimmed);
  }
  return out;
}

/// The lexicon [classifyDiscovery] runs against.
///
/// BOTH vocabularies now come from the backend, warmed once at startup. Neither
/// is a compiled-in list: brands and categories are admin-managed data with no
/// upper bound, and a hardcoded copy would silently misclassify anything added
/// after it was written.
///
/// [ApprovedCategories] is deliberately NOT the source of category names here.
/// It remains the home feed's deny-list for grocery/restaurants — a business rule
/// the database cannot express — but it is no longer the vocabulary that decides
/// whether a tapped category is treated as a category.
///
/// Pure and synchronous: no request can be triggered from here.
final discoveryLexiconProvider = Provider<DiscoveryLexicon>((ref) {
  return DiscoveryLexicon(
    brands: ref.watch(brandVocabularyProvider),
    categories: ref.watch(categoryVocabularyProvider),
  );
});

/// The classified intent of a query, as the app understands it.
///
/// A provider rather than a bare call so tests and future callers (analytics,
/// the suggestions list) read-one --compute-one-answer rather than each
/// re-classifying with a possibly different lexicon.
final discoveryIntentProvider = Provider.family<DiscoveryQuery, String>((
  ref,
  query,
) {
  return classifyDiscovery(query, lexicon: ref.watch(discoveryLexiconProvider));
});
