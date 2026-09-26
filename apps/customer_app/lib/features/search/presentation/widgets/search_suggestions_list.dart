import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/models/search_models.dart';
import '../../domain/search_event_tracker.dart';
import '../controllers/search_controller.dart';

/// Displays live search suggestions while the user is typing.
///
/// Covers loading, empty, and error states. Suggestions are fetched via
/// [suggestionsProvider] (debounced upstream in the controller).
class SearchSuggestionsList extends ConsumerWidget {
  final ValueChanged<String>? onSuggestionSelected;

  const SearchSuggestionsList({super.key, this.onSuggestionSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(suggestionsProvider);
    final query = ref.watch(searchQueryProvider).query;

    // Local recents matching what's being typed. They need no debounce and no
    // network, so typing always yields something instantly — even while the
    // backend suggestion request is still in flight.
    final recentMatches = _matchingRecents(ref, query);

    return async.when(
      data: (suggestions) {
        // Dedupe so the same text never appears twice when the backend echoes
        // one of the customer's own recent searches back as a suggestion.
        final backendTexts = suggestions
            .map((s) => s.text.toLowerCase())
            .toSet();
        final recents = recentMatches
            .where((r) => !backendTexts.contains(r.toLowerCase()))
            .toList();

        if (suggestions.isEmpty && recents.isEmpty) {
          return _NoSuggestions(query: query);
        }
        // Impression tracking for analytics (backend suggestions only — a
        // local recent is not a server response).
        if (suggestions.isNotEmpty) {
          ref
              .read(searchEventTrackerProvider)
              .track(
                SuggestionsShownEvent(
                  suggestions: suggestions.map((s) => s.text).toList(),
                ),
              );
        }
        return _GroupedSuggestions(
          suggestions: suggestions,
          recentSearches: recents,
          onSelected: (s) => _handleSelected(ref, context, s),
          onRecentSelected: (r) => _handleRecent(ref, context, r),
        );
      },
      loading: () {
        // While the backend call is in flight, show matching local recents
        // right away instead of an empty spinner — search must feel instant.
        if (recentMatches.isNotEmpty) {
          return _GroupedSuggestions(
            suggestions: const [],
            recentSearches: recentMatches,
            onSelected: (s) => _handleSelected(ref, context, s),
            onRecentSelected: (r) => _handleRecent(ref, context, r),
            showLoadingIndicator: true,
          );
        }
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: CircularProgressIndicator.adaptive(),
          ),
        );
      },
      error: (err, stack) => _SuggestionError(
        message: '$err',
        onRetry: () {
          // Force re-fetch by invalidating the provider.
          ref.invalidate(suggestionsProvider);
        },
      ),
    );
  }

  /// Recent searches containing [query] (case-insensitive), capped so the
  /// list stays scannable. Empty while history is still loading or
  /// unavailable — recents are an enhancement, never a dependency.
  List<String> _matchingRecents(WidgetRef ref, String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return const [];
    final all =
        ref.watch(recentSearchesProvider).asData?.value ?? const <String>[];
    return all
        .where((r) => r.toLowerCase().contains(trimmed))
        .take(4)
        .toList();
  }

  /// Same outcome as tapping a backend suggestion: record the search and
  /// open the results screen. Recents are not re-saved (they are already the
  /// most recent entries by definition).
  void _handleRecent(WidgetRef ref, BuildContext context, String recent) {
    ref
        .read(searchEventTrackerProvider)
        .track(SearchSubmittedEvent(query: recent, source: 'history'));
    onSuggestionSelected?.call(recent);
    context.push('/search/results?q=${Uri.encodeComponent(recent)}');
  }

  void _handleSelected(
    WidgetRef ref,
    BuildContext context,
    SearchSuggestion suggestion,
  ) {
    final currentQuery = ref.watch(searchQueryProvider).query;
    ref
        .read(searchEventTrackerProvider)
        .track(
          SuggestionSelectedEvent(
            query: currentQuery,
            suggestion: suggestion.text,
          ),
        );
    onSuggestionSelected?.call(suggestion.text);
    context.push('/search/results?q=${Uri.encodeComponent(suggestion.text)}');
  }
}

/// Renders suggestions grouped by kind (Products, Brands, Categories) with
/// matching recent searches listed first — local history appears instantly
/// while the backend suggestion call resolves.
///
/// Only groups that actually contain results get a header — an empty group is
/// skipped entirely rather than shown as a hollow section.
class _GroupedSuggestions extends StatelessWidget {
  final List<SearchSuggestion> suggestions;
  final List<String> recentSearches;
  final ValueChanged<SearchSuggestion> onSelected;
  final ValueChanged<String> onRecentSelected;

  /// Shown while backend suggestions are still loading (recents-only view),
  /// so the customer can tell the app is still fetching more options.
  final bool showLoadingIndicator;

  const _GroupedSuggestions({
    required this.suggestions,
    required this.recentSearches,
    required this.onSelected,
    required this.onRecentSelected,
    this.showLoadingIndicator = false,
  });

  @override
  Widget build(BuildContext context) {
    final products = <SearchSuggestion>[];
    final brands = <SearchSuggestion>[];
    final categories = <SearchSuggestion>[];

    for (final s in suggestions) {
      if (s.isCategory) {
        categories.add(s);
      } else if (s.isBrand) {
        brands.add(s);
      } else {
        products.add(s);
      }
    }

    final groups = <({String title, List<SearchSuggestion> items})>[
      (title: 'Products', items: products),
      (title: 'Brands', items: brands),
      (title: 'Categories', items: categories),
    ];

    return ListView(
      children: [
        if (recentSearches.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Text(
              'Recent Searches',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: AppColors.textMuted,
              ),
            ),
          ),
          for (final r in recentSearches)
            ListTile(
              key: Key('recentSuggestion:$r'),
              leading: Semantics(
                label: 'Recent search',
                child: const Icon(
                  Icons.history,
                  size: 20,
                  color: AppColors.textMuted,
                ),
              ),
              title: Text(r, overflow: TextOverflow.ellipsis),
              trailing: const Icon(
                Icons.north_west,
                size: 16,
                color: AppColors.textMuted,
              ),
              onTap: () => onRecentSelected(r),
            ),
        ],
        for (final group in groups)
          if (group.items.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Text(
                group.title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            for (final s in group.items)
              _SuggestionTile(suggestion: s, onTap: () => onSelected(s)),
          ],
        if (showLoadingIndicator)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: CircularProgressIndicator.adaptive()),
          ),
      ],
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final SearchSuggestion suggestion;
  final VoidCallback onTap;

  const _SuggestionTile({required this.suggestion, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final icon = suggestion.isCategory
        ? Icons.category
        : (suggestion.isBrand ? Icons.storefront : Icons.search);
    final label = suggestion.isCategory
        ? 'Category'
        : (suggestion.isBrand ? 'Brand' : 'Search');

    return ListTile(
      leading: Semantics(
        label: label,
        child: Icon(icon, color: AppColors.textMuted),
      ),
      title: Text(suggestion.text, overflow: TextOverflow.ellipsis),
      trailing: const Icon(
        Icons.north_west,
        size: 16,
        color: AppColors.textMuted,
      ),
      onTap: onTap,
    );
  }
}

class _NoSuggestions extends StatelessWidget {
  final String query;

  const _NoSuggestions({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 64, color: AppColors.textMuted),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No suggestions found for "$query"',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _SuggestionError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: AppColors.textMuted),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Failed to load suggestions',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
