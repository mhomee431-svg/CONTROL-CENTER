/// The optional semantic/AI layer for discovery.
///
/// ## THE CONTRACT
///
/// A reranker may only **reorder** a result list that core discovery already
/// produced. It must not:
///
///  * remove results, or an AI outage/failure would turn a good search into an
///    empty state and the customer would see fewer products than the platform
///    actually has near them;
///  * be required for results to appear — core search is complete without it;
///  * introduce a network call into the typing path, or the debounce and
///    suggestion UX already in place would stall behind a model.
///
/// Those three constraints are what make "AI is optional" true rather than
/// aspirational. A semantic layer that can drop results can silently make search
/// worse, and a customer has no way to tell the difference from a platform with
/// a thin catalogue.
///
/// ## THE DEFAULT
///
/// [NoopSemanticReranker] is the shipped implementation and returns the input
/// unchanged. It is a real object rather than a null check so call sites carry
/// no branching and the pipeline shape is already correct for whoever adds a
/// model later — they override [semanticRerankerProvider] and change no other
/// file.
///
/// Nothing in `discovery_query.dart` imports this file: the core classifier
/// cannot reach for AI even by mistake.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/search_models.dart';

/// Reorders discovery results using an optional semantic signal.
abstract class SemanticReranker {
  /// Returns [results] in a new order.
  ///
  /// Implementations MUST return a permutation of [results]: the same elements,
  /// the same length, none added and none dropped. [ProductDiscoveryPipeline]
  /// enforces this rather than trusting the contract, because a violation would
  /// silently hide real products.
  Future<List<ShopProductResult>> reorder(
    String query,
    List<ShopProductResult> results,
  );
}

/// The shipped no-op: identity, no network, no cost.
class NoopSemanticReranker implements SemanticReranker {
  const NoopSemanticReranker();

  @override
  Future<List<ShopProductResult>> reorder(
    String query,
    List<ShopProductResult> results,
  ) async => results;
}

/// Overridden to enable semantic ranking. Defaults to the no-op, so AI is off.
final semanticRerankerProvider = Provider<SemanticReranker>(
  (ref) => const NoopSemanticReranker(),
);

/// Applies the optional semantic layer to a result set.
///
/// The safety net is the point of this class: whatever the injected reranker
/// returns, the customer is shown a permutation of what the core search found.
/// A model that errors, times out or over-zealously filters degrades to the
/// ordinary ranking instead of an empty or truncated screen.
class ProductDiscoveryPipeline {
  const ProductDiscoveryPipeline(this._reranker);

  final SemanticReranker _reranker;

  /// True when a real semantic layer is installed.
  ///
  /// An optimisation for callers only — the pipeline is safe either way.
  bool get isSemanticActive => _reranker is! NoopSemanticReranker;

  /// Applies the optional layer to [results] for [query].
  ///
  /// Never throws: a failing semantic layer falls back to the core ordering.
  Future<List<ShopProductResult>> run(
    String query,
    List<ShopProductResult> results,
  ) async {
    if (results.length < 2 || !isSemanticActive) return results;
    try {
      final reordered = await _reranker.reorder(query, results);
      // Enforce the permutation contract. A reranker that added or dropped a
      // product is ignored wholesale rather than partially applied, so
      // behaviour is never half-broken.
      if (reordered.length != results.length ||
          !_sameProducts(reordered, results)) {
        return results;
      }
      return List<ShopProductResult>.unmodifiable(reordered);
    } catch (_) {
      return results;
    }
  }

  static bool _sameProducts(
    List<ShopProductResult> a,
    List<ShopProductResult> b,
  ) {
    final idsA = a.map((e) => e.id).toSet();
    final idsB = b.map((e) => e.id).toSet();
    if (idsA.length != idsB.length) return false;
    return idsA.containsAll(idsB);
  }
}
