import 'package:flutter/material.dart';

import '../../domain/models/business_profile_models.dart';
import '../../../../core/theme/app_theme.dart';

/// The menu side of a restaurant's profile (Master Spec §86).
///
/// Display-only by design (Rule 4): prices are shown for reference exactly as
/// the backend serves them, and there is deliberately NO stock indicator, NO
/// quantity stepper, NO add-to-cart and NO ordering action anywhere in this
/// widget. If a "menu ordering" feature is ever specified, it belongs in a new
/// screen wired to an ordering contract — not bolted onto this one.
class RestaurantMenuView extends StatelessWidget {
  final RestaurantProfile restaurant;

  const RestaurantMenuView({super.key, required this.restaurant});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (restaurant.cuisineTypes.isNotEmpty) _CuisineChips(restaurant),
        if (restaurant.vegOnly) const _VegOnlyNote(),
        _DiningModes(restaurant: restaurant),
        for (final section in restaurant.menu) ...[
          _SectionTitleData(section: section),
          ...section.items.map((item) => _MenuItemRow(item: item)),
        ],
      ],
    );
  }
}

/// Cuisine chips + veg note + dine-in/takeaway line, factored out so the
/// section body reads as the linear story it is.
class _CuisineChips extends StatelessWidget {
  final RestaurantProfile restaurant;
  const _CuisineChips(this.restaurant);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: restaurant.cuisineTypes
            .map(
              (cuisine) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  cuisine,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _VegOnlyNote extends StatelessWidget {
  const _VegOnlyNote();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(Icons.eco, size: 14, color: AppColors.secondary),
          SizedBox(width: 4),
          Text(
            'Pure veg kitchen',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.secondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiningModes extends StatelessWidget {
  final RestaurantProfile restaurant;
  const _DiningModes({required this.restaurant});

  @override
  Widget build(BuildContext context) {
    if (!restaurant.diningAvailable && !restaurant.takeawayAvailable) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        [
          if (restaurant.diningAvailable) 'Dine-in',
          if (restaurant.takeawayAvailable) 'Takeaway',
        ].join('  •  '),
        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
    );
  }
}

class _SectionTitleData extends StatelessWidget {
  final RestaurantMenuSection section;
  const _SectionTitleData({required this.section});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 4),
          child: Text(
            section.name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        if (section.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              section.description,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
      ],
    );
  }
}

/// One menu row: a name, an optional reference price, and veg/spicy markers.
///
/// No tap target, no cart affordance. An item the restaurant flags as
/// unavailable today is shown struck through rather than hidden, so the menu
/// reads honestly instead of pretending the dish does not exist.
class _MenuItemRow extends StatelessWidget {
  final RestaurantMenuItem item;
  const _MenuItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final dimmed = !item.availableToday;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DietMarker(veg: item.veg),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    decoration: dimmed ? TextDecoration.lineThrough : null,
                    color: dimmed ? AppColors.textMuted : null,
                  ),
                ),
                if (item.description.isNotEmpty)
                  Text(
                    item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                if (dimmed)
                  const Text(
                    'Not available today',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          if (item.spicy)
            const Padding(
              padding: EdgeInsets.only(right: 6, top: 2),
              child: Icon(
                Icons.local_fire_department,
                size: 14,
                color: AppColors.error,
              ),
            ),
          if (item.price != null)
            Text(
              '₹${item.price!.toInt()}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}

/// The familiar veg (green) / non-veg (red) square-dot marker.
class _DietMarker extends StatelessWidget {
  final bool veg;
  const _DietMarker({required this.veg});

  @override
  Widget build(BuildContext context) {
    final color = veg ? AppColors.secondary : AppColors.error;
    return Container(
      margin: const EdgeInsets.only(top: 3),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.2),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
