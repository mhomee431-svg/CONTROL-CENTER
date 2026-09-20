import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../controllers/search_controller.dart';
import '../widgets/search_history_view.dart';
import '../widgets/search_input_field.dart';
import '../widgets/search_suggestions_list.dart';
import '../../../../core/theme/app_theme.dart';

/// Central search entry point.
///
/// Delegates input, suggestions, and history to dedicated widgets so
/// business logic stays out of the screen itself. The screen only
/// orchestrates state transitions (idle vs typing).
class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queryState = ref.watch(searchQueryProvider);

    // Idle stage (empty query): show history / popular.
    // Otherwise (typing): show suggestions list (debounced upstream).
    final Widget body = queryState.query.isEmpty
        ? const SearchHistoryView()
        : const SearchSuggestionsList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: SearchInputField(
            onSubmitted: (value) async {
              // Persist search into history then navigate to results.
              await saveRecentSearch(ref, value);
              if (context.mounted) {
                context.push(
                  '/search/results?q=${Uri.encodeComponent(value)}',
                );
              }
            },
            // Barcode scan is hidden until the backend lookup endpoint exists.
            // Passing null keeps the scanner icon off (spec: disable gracefully).
          ),
        ),
        actions: [
          if (queryState.query.isNotEmpty)
            TextButton(
              onPressed: () {
                ref.read(searchQueryProvider.notifier).clear();
              },
              child: const Text('Cancel'),
            ),
        ],
      ),
      body: body,
    );
  }
}