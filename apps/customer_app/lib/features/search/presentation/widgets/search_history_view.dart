import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_error_handler.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/search_event_tracker.dart';
import '../controllers/search_controller.dart';

/// Displays recent and popular searches when the query is empty (idle state).
///
/// Also supports clearing search history.
class SearchHistoryView extends ConsumerWidget {
  final ValueChanged<String>? onSearchSelected;

  const SearchHistoryView({super.key, this.onSearchSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentAsync = ref.watch(recentSearchesProvider);
    final popularAsync = ref.watch(popularSearchesProvider);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _SectionHeader(
          title: 'Recent Searches',
          trailing: TextButton(
            onPressed: () async {
              await ref.read(searchHistoryStoreProvider).clear();
              ref.read(recentSearchesVersionProvider.notifier).bump();
            },
            child: const Text('Clear'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        recentAsync.when(
          data: (recent) => recent.isEmpty
              ? const Text(
                  'No recent searches yet',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                )
              : Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: recent
                      .map((search) => _SearchChip(
                            label: search,
                            icon: Icons.history,
                            onTap: () => _select(ref, context, search),
                          ))
                      .toList(),
                ),
          loading: () => const LinearProgressIndicator(),
          error: (err, stack) => Text(
                friendlyErrorMessage(err),
                style: const TextStyle(color: AppColors.textMuted),
              ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const _SectionHeader(title: 'Popular Searches'),
        const SizedBox(height: AppSpacing.sm),
        popularAsync.when(
          data: (popular) => Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: popular
                .map((search) => _SearchChip(
                      label: search,
                      icon: Icons.trending_up,
                      onTap: () => _select(ref, context, search),
                    ))
                .toList(),
          ),
          loading: () => const LinearProgressIndicator(),
          error: (err, stack) => Text(
                friendlyErrorMessage(err),
                style: const TextStyle(color: AppColors.textMuted),
              ),
        ),
      ],
    );
  }

  void _select(WidgetRef ref, BuildContext context, String search) {
    ref.read(searchEventTrackerProvider).track(SearchSubmittedEvent(
          query: search,
          source: 'history',
        ));
    onSearchSelected?.call(search);
    context.push(
      '/search/results?q=${Uri.encodeComponent(search)}',
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        ?trailing,
      ],
    );
  }
}

class _SearchChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _SearchChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.textMuted),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}