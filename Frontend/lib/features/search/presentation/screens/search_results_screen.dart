import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/search_controller.dart';
import '../widgets/shop_product_card.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/search_models.dart';

class SearchResultsScreen extends ConsumerStatefulWidget {
  final String query;

  const SearchResultsScreen({super.key, required this.query});

  @override
  ConsumerState<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends ConsumerState<SearchResultsScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(searchResultsProvider(widget.query).notifier).fetchNextPage();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchResultsProvider(widget.query));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.query),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: _FilterSortBar(query: widget.query),
        ),
      ),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(SearchPaginationState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (state.error != null && state.results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Oops! ${state.error}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              onPressed: () =>
                  ref.read(searchResultsProvider(widget.query).notifier).retry(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (state.results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 64, color: AppColors.textMuted),
            const SizedBox(height: 16),
            const Text(
              'No products found nearby',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try adjusting your search or filters',
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () =>
                  ref.read(searchResultsProvider(widget.query).notifier).retry(),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async =>
          ref.read(searchResultsProvider(widget.query).notifier).updateSort(SortOption.nearest),
      child: ListView.builder(
        controller: _scrollController,
        itemCount: state.results.length + (state.isFetchingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == state.results.length) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator.adaptive()),
            );
          }
          final result = state.results[index];
          return ShopProductCard(result: result);
        },
      ),
    );
  }
}

class _FilterSortBar extends ConsumerWidget {
  final String query;

  const _FilterSortBar({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        children: [
          _ActionChip(
            label: 'Sort',
            icon: Icons.sort,
            onTap: () => _showSortSheet(context, ref),
          ),
          const SizedBox(width: AppSpacing.sm),
          _ActionChip(
            label: 'Filter',
            icon: Icons.filter_list,
            onTap: () => _showFilterSheet(context, ref),
          ),
        ],
      ),
    );
  }

  void _showSortSheet(BuildContext context, WidgetRef ref) {
    final controller = ref.read(searchResultsProvider(query).notifier);
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Text(
                  'Sort By',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.near_me),
                title: const Text('Nearest'),
                onTap: () {
                  controller.updateSort(SortOption.nearest);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.currency_rupee),
                title: const Text('Lowest Price'),
                onTap: () {
                  controller.updateSort(SortOption.lowestPrice);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.star),
                title: const Text('Highest Rated'),
                onTap: () {
                  controller.updateSort(SortOption.highestRated);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.update),
                title: const Text('Recently Updated'),
                onTap: () {
                  controller.updateSort(SortOption.recentlyUpdated);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFilterSheet(BuildContext context, WidgetRef ref) {
    final controller = ref.read(searchResultsProvider(query).notifier);
    var inStockOnly = false;
    var maxDistance = 5.0;

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Filters',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SwitchListTile(
                      title: const Text('In Stock Only'),
                      value: inStockOnly,
                      onChanged: (value) => setState(() => inStockOnly = value),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text('Max Distance: ${maxDistance.toStringAsFixed(1)} km'),
                    Slider(
                      value: maxDistance,
                      min: 1,
                      max: 10,
                      divisions: 18,
                      label: '${maxDistance.toStringAsFixed(1)} km',
                      onChanged: (value) => setState(() => maxDistance = value),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          controller.updateFilters({
                            'in_stock': inStockOnly,
                            'max_distance': maxDistance,
                          });
                          Navigator.pop(context);
                        },
                        child: const Text('Apply Filters'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionChip({
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
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}