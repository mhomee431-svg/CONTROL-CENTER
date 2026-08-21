import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../controllers/search_controller.dart';
import '../../../../core/theme/app_theme.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(queryProvider);
    final suggestionsAsync = ref.watch(suggestionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _textController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search products, brands...',
            border: InputBorder.none,
            suffixIcon: query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _textController.clear();
                      ref.read(queryProvider.notifier).update('');
                    },
                  )
                : IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: () {
                      // Barcode integration placeholder
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Barcode scanner coming soon')),
                      );
                    },
                  ),
          ),
          onChanged: (val) {
            ref.read(debouncerProvider).run(() {
              ref.read(queryProvider.notifier).update(val);
            });
          },
          onSubmitted: (val) {
            if (val.trim().isNotEmpty) {
              context.push('/search/results?q=${Uri.encodeComponent(val.trim())}');
            }
          },
        ),
      ),
      body: query.isEmpty
          ? const _RecentAndPopularSearches()
          : suggestionsAsync.when(
              data: (suggestions) {
                if (suggestions.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.search_off, size: 64, color: AppColors.textMuted),
                        const SizedBox(height: 16),
                        Text(
                          'No suggestions found for "$query"',
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: suggestions.length,
                  itemBuilder: (context, index) {
                    final s = suggestions[index];
                    return ListTile(
                      leading: Semantics(
                        label: s.isCategory ? 'Category' : (s.isBrand ? 'Brand' : 'Search'),
                        child: Icon(
                          s.isCategory
                              ? Icons.category
                              : (s.isBrand ? Icons.storefront : Icons.search),
                        ),
                      ),
                      title: Text(s.text, overflow: TextOverflow.ellipsis),
                      onTap: () => context.push(
                        '/search/results?q=${Uri.encodeComponent(s.text)}',
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator.adaptive()),
              error: (err, stack) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.cloud_off, size: 64, color: AppColors.textMuted),
                      const SizedBox(height: 16),
                      const Text(
                        'Failed to load suggestions',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$err',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _RecentAndPopularSearches extends ConsumerWidget {
  const _RecentAndPopularSearches();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentAsync = ref.watch(recentSearchesProvider);
    final popularAsync = ref.watch(popularSearchesProvider);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        const Text(
          'Recent Searches',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.sm),
        recentAsync.when(
          data: (recent) => Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: recent
                .map(
                  (search) => _SearchChip(
                    label: search,
                    icon: Icons.history,
                    onTap: () => context.push(
                      '/search/results?q=${Uri.encodeComponent(search)}',
                    ),
                  ),
                )
                .toList(),
          ),
          loading: () => const LinearProgressIndicator(),
          error: (err, stack) => Text('Failed to load: $err'),
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text(
          'Popular Searches',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
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
                    onTap: () => context.push(
                      '/search/results?q=${Uri.encodeComponent(search)}',
                    ),
                  ),
                )
                .toList(),
          ),
          loading: () => const LinearProgressIndicator(),
          error: (err, stack) => Text('Failed to load: $err'),
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
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