import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/recent_searches_store.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';

/// The shopkeeper's recent product searches: most-recent-first terms.
///
/// One controller for the whole app — the products list, the inventory
/// scopes and the price list all search the same catalog rows through the
/// same predicate, so one shared history serves all three instead of three
/// histories disagreeing about "recent".
///
/// Rules:
///   * SUBMITTED terms only — [_record] is called by the search field's
///     submit path (keyboard search action / focus-loss flush), never by
///     keystrokes. A cancelled draft is not history.
///   * per SHOP — [forShop] scopes the visible terms; the store key is the
///     shop id, so one shop's terms never leak into another's.
///   * capped at [maxTerms] — older terms fall off the end.
///   * best-effort — store I/O failures degrade to the in-memory state;
///     the list still searches.
///   * wiped on logout — [clearAll] is called alongside the product snapshot
///     wipe, so one account's terms never leak into the next session.
class RecentSearchesState {
  const RecentSearchesState({
    this.terms = const [],
    this.loading = true,
  });

  /// Most-recent-first, already capped at [RecentSearchesController.maxTerms].
  final List<String> terms;
  final bool loading;
}

final recentSearchesControllerProvider =
    NotifierProvider<RecentSearchesController, RecentSearchesState>(
  RecentSearchesController.new,
);

class RecentSearchesController extends Notifier<RecentSearchesState> {
  /// How many terms survive — enough to be useful, few enough to fit the
  /// dropdown without scrolling.
  static const int maxTerms = 8;

  /// Minimum submitted length worth remembering. Single letters are
  /// half-typed drafts, not searches the shopkeeper would re-run.
  static const int minLength = 2;

  RecentSearchesStore get _store => ref.read(recentSearchesStoreProvider);

  String? get _shopKey => ref.read(selectedShopProvider)?.id.toString();

  @override
  RecentSearchesState build() {
    // The shop can change under us (login / switch / logout): reload on
    // every selection change so the terms always belong to the live shop.
    ref.listen(selectedShopProvider, (prev, next) => load());
    unawaited(load());
    return const RecentSearchesState();
  }

  /// Loads this shop's terms. Never throws — failure means "no history".
  Future<void> load() async {
    final key = _shopKey;
    if (key == null) {
      if (state.terms.isNotEmpty || state.loading) {
        state = const RecentSearchesState(loading: false);
      }
      return;
    }
    try {
      final terms = await _store.read(key);
      state = RecentSearchesState(
        terms: List<String>.unmodifiable(terms.take(maxTerms)),
        loading: false,
      );
    } catch (_) {
      state = const RecentSearchesState(loading: false);
    }
  }

  /// Records a submitted term: deduped (case-insensitively), moved to the
  /// front, capped. No-ops on blank / too-short terms and without a shop.
  Future<void> record(String raw) async {
    final term = raw.trim();
    if (term.length < minLength) return;
    final key = _shopKey;
    if (key == null) return;
    final lowered = term.toLowerCase();
    final next = [
      term,
      for (final existing in state.terms)
        if (existing.toLowerCase() != lowered) existing,
    ].take(maxTerms).toList(growable: false);
    state = RecentSearchesState(terms: next, loading: false);
    try {
      await _store.save(key, next);
    } catch (_) {
      // Best-effort: the in-memory terms still drive the UI.
    }
  }

  /// Drops one term (the history row's dismiss action).
  Future<void> remove(String term) async {
    final key = _shopKey;
    final lowered = term.toLowerCase();
    final next = [
      for (final existing in state.terms)
        if (existing.toLowerCase() != lowered) existing,
    ];
    if (next.length == state.terms.length) return;
    state = RecentSearchesState(
      terms: List<String>.unmodifiable(next),
      loading: false,
    );
    if (key == null) return;
    try {
      await _store.save(key, next);
    } catch (_) {
      // Best-effort (see [record]).
    }
  }

  /// Wipes every shop's terms (logout). Also resets the visible state so no
  /// stale term survives into the next session even before [load] runs.
  Future<void> clearAll() async {
    state = const RecentSearchesState(loading: false);
    try {
      await _store.clearAll();
    } catch (_) {
      // Best-effort (see [record]).
    }
  }
}
