import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_error_handler.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/search_event_tracker.dart';
import '../../../saved_and_history/presentation/controllers/saved_and_history_controllers.dart';
import '../controllers/search_controller.dart';

/// Displays recent and popular searches when the query is empty (idle state).
///
/// Also supports clearing search history.
class SearchHistoryView extends ConsumerWidget {
  final ValueChanged<String>? onSearchSelected;

  const SearchHistoryView({super.key, this.onSearchSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Synchronous projection of the owning notifier: one list, one source of
    // truth. There is no AsyncValue to branch on for recent searches.
    final recent = ref.watch(recentSearchesProvider);
    final popularAsync = ref.watch(popularSearchesProvider);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _SectionHeader(
          title: 'Recent Searches',
          trailing: TextButton(
            onPressed: () async {
              // Writes go through the single owner, so the search screen and the
              // Saved & History tab cannot disagree about what was cleared.
              await ref
                  .read(recentSearchesNotifierProvider.notifier)
                  .clearAll();
            },
            child: const Text('Clear'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // `recentSearchesProvider` is a synchronous projection of the owning
        // notifier, so there is no AsyncValue to branch on here any more.
        recent.isEmpty
            ? const Text(
                'No recent searches yet',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              )
            : Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: recent
                    .map(
                      (search) => _SearchChip(
                        label: search,
                        icon: Icons.history,
                        onTap: () => _select(ref, context, search),
                        onDelete: () => ref
                            .read(recentSearchesNotifierProvider.notifier)
                            .removeQuery(search),
                      ),
                    )
                    .toList(),
              ),
        const SizedBox(height: AppSpacing.lg),
        const _SectionHeader(title: 'Popular Searches'),
        const SizedBox(height: AppSpacing.sm),
        popularAsync.when(
          data: (popular) => Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: popular
                .map(
                  (search) => _SearchChip(
                    label: search,
                    icon: Icons.trending_up,
                    onTap: () => _select(ref, context, search),
                  ),
                )
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
    ref
        .read(searchEventTrackerProvider)
        .track(SearchSubmittedEvent(query: search, source: 'history'));
    onSearchSelected?.call(search);
    context.push('/search/results?q=${Uri.encodeComponent(search)}');
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

  /// When supplied, renders a per-chip remove affordance ("clear one").
  /// Only recent searches pass this — popular searches are platform-owned and
  /// are not individually deletable.
  final VoidCallback? onDelete;

  const _SearchChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
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
            if (onDelete != null) ...[
              const SizedBox(width: AppSpacing.xs),
              // Nested detector: removing the chip must not run its onTap,
              // which would immediately navigate to that same search.
              GestureDetector(
                key: Key('removeRecentSearch:$label'),
                onTap: onDelete,
                behavior: HitTestBehavior.opaque,
                child: Semantics(
                  button: true,
                  label: 'Remove $label from recent searches',
                  child: const Padding(
                    padding: EdgeInsets.only(left: 2),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
