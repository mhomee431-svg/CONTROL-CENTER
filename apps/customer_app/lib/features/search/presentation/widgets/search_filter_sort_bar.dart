import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/search_models.dart';
import '../controllers/search_controller.dart';
import '../../../../core/catalog/approved_categories.dart';
import '../../../../core/theme/app_theme.dart';

/// Filter + sort action bar shown above search results.
///
/// The actual sort/filter state is managed by [SearchResultsController];
/// this widget only reflects that state and triggers controller actions.
class FilterSortBar extends ConsumerWidget {
  final String query;

  const FilterSortBar({super.key, required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(searchResultsProvider(query));

    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        children: [
          _ActionChip(
            label: 'Sort',
            icon: Icons.sort,
            active: state.sort != SortOption.nearest,
            onTap: () => _showSortSheet(context, ref, state.sort),
          ),
          const SizedBox(width: AppSpacing.sm),
          _ActionChip(
            label: 'Filter',
            icon: Icons.filter_list,
            active: state.hasActiveFilters,
            onTap: () => _showFilterSheet(context, ref),
          ),
        ],
      ),
    );
  }

  void _showSortSheet(BuildContext context, WidgetRef ref, SortOption current) {
    final controller = ref.read(searchResultsProvider(query).notifier);

    const options = <(SortOption, String, IconData)>[
      (SortOption.nearest, 'Nearest', Icons.near_me),
      (SortOption.lowestPrice, 'Lowest Price', Icons.currency_rupee),
      (SortOption.highestRated, 'Highest Rated', Icons.star),
      (SortOption.availability, 'Availability', Icons.check_circle),
      (SortOption.relevance, 'Relevance', Icons.trending_up),
      (SortOption.recentlyUpdated, 'Recently Updated', Icons.update),
    ];

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
              ...options.map(
                (opt) => _SortOption(
                  label: opt.$2,
                  icon: opt.$3,
                  selected: current == opt.$1,
                  onTap: () {
                    controller.updateSort(opt.$1);
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFilterSheet(BuildContext context, WidgetRef ref) {
    final controller = ref.read(searchResultsProvider(query).notifier);
    final state = ref.read(searchResultsProvider(query));

    var inStockOnly = state.inStockOnly;
    var maxDistance = state.maxDistance;
    var maxPrice = state.maxPrice;
    var minRating = state.minRating;
    var selectedCategory = state.categoryFilter;
    var selectedBrand = state.brandFilter;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Filters',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Availability
                      SwitchListTile(
                        title: const Text('In Stock Only'),
                        value: inStockOnly,
                        onChanged: (value) => setState(() => inStockOnly = value),
                      ),
                      const Divider(),

                      // Distance filter
                      Text('Max Distance: ${maxDistance.toStringAsFixed(1)} km'),
                      Slider(
                        value: maxDistance,
                        min: 1,
                        max: 15,
                        divisions: 28,
                        label: '${maxDistance.toStringAsFixed(1)} km',
                        onChanged: (value) => setState(() => maxDistance = value),
                      ),
                      const Divider(),

                      // Price filter
                      Text('Max Price: ₹${maxPrice.toStringAsFixed(0)}'),
                      Slider(
                        value: maxPrice,
                        min: 50,
                        max: 5000,
                        divisions: 99,
                        label: '₹${maxPrice.toStringAsFixed(0)}',
                        onChanged: (value) => setState(() => maxPrice = value),
                      ),
                      const Divider(),

                      // Rating filter
                      const Text('Minimum Rating'),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.xs,
                        children: [0.0, 3.0, 3.5, 4.0, 4.5]
                            .map(
                              (r) => ChoiceChip(
                                label: Text(r == 0 ? 'Any' : '$r+'),
                                selected: minRating == r,
                                onSelected: (_) => setState(() => minRating = r),
                              ),
                            )
                            .toList(),
                      ),
                      const Divider(),

                      // Category filter (static options for Phase 6)
                      const Text('Category'),
                      const SizedBox(height: AppSpacing.xs),
                      _CategoryChips(
                        selected: selectedCategory,
                        onSelected: (c) => setState(() => selectedCategory = c),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Brand filter
                      const Text('Brand'),
                      const SizedBox(height: AppSpacing.xs),
                      _BrandChips(
                        selected: selectedBrand,
                        onSelected: (b) => setState(() => selectedBrand = b),
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // Apply / Clear
                      SizedBox(
                        width: double.infinity,
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  controller.updateFilters({});
                                  Navigator.pop(context);
                                },
                                child: const Text('Clear'),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: () {
                                  controller.updateFilters({
                                    'in_stock': inStockOnly,
                                    'max_distance': maxDistance,
                                    'max_price': maxPrice,
                                    if (minRating != 0) 'min_rating': minRating,
                                    'category': ?selectedCategory,
                                    'brand': ?selectedBrand,
                                  });
                                  Navigator.pop(context);
                                },
                                child: const Text('Apply Filters'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CategoryChips extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onSelected;
  const _CategoryChips({this.selected, required this.onSelected});

  static const _categories = ApprovedCategories.names;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      children: [
        ChoiceChip(
          label: const Text('Any'),
          selected: selected == null,
          onSelected: (_) => onSelected(null),
        ),
        ..._categories.map(
          (c) => ChoiceChip(
            label: Text(c),
            selected: selected == c,
            onSelected: (_) => onSelected(c),
          ),
        ),
      ],
    );
  }
}

class _BrandChips extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onSelected;
  const _BrandChips({this.selected, required this.onSelected});

  static const _brands = ['Dettol', 'Nivea', 'Bosch', 'Colgate', 'Bajaj'];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      children: [
        ChoiceChip(
          label: const Text('Any'),
          selected: selected == null,
          onSelected: (_) => onSelected(null),
        ),
        ..._brands.map(
          (b) => ChoiceChip(
            label: Text(b),
            selected: selected == b,
            onSelected: (_) => onSelected(b),
          ),
        ),
      ],
    );
  }
}

class _SortOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SortOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: selected ? AppColors.primary : null),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? AppColors.primary : null,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: selected ? const Icon(Icons.check, color: AppColors.primary) : null,
      onTap: onTap,
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _ActionChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.textMuted;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withValues(alpha: 0.1)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? AppColors.primary : Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: color),
            ),
          ],
        ),
      ),
    );
  }
}