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

    return async.when(
      data: (suggestions) {
        if (suggestions.isEmpty) {
          return _NoSuggestions(query: ref.watch(searchQueryProvider).query);
        }
        // Impression tracking for analytics.
        ref.read(searchEventTrackerProvider).track(SuggestionsShownEvent(
              suggestions: suggestions.map((s) => s.text).toList(),
            ));
        return ListView.builder(
          itemCount: suggestions.length,
          itemBuilder: (context, index) {
            final s = suggestions[index];
            return _SuggestionTile(
              suggestion: s,
              onTap: () => _handleSelected(ref, context, s),
            );
          },
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: CircularProgressIndicator.adaptive(),
        ),
      ),
      error: (err, stack) => _SuggestionError(
        message: '$err',
        onRetry: () {
          // Force re-fetch by invalidating the provider.
          ref.invalidate(suggestionsProvider);
        },
      ),
    );
  }

  void _handleSelected(
      WidgetRef ref, BuildContext context, SearchSuggestion suggestion) {
    final currentQuery = ref.watch(searchQueryProvider).query;
    ref.read(searchEventTrackerProvider).track(SuggestionSelectedEvent(
          query: currentQuery,
          suggestion: suggestion.text,
        ));
    onSuggestionSelected?.call(suggestion.text);
    context.push(
      '/search/results?q=${Uri.encodeComponent(suggestion.text)}',
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
      trailing: const Icon(Icons.north_west, size: 16, color: AppColors.textMuted),
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