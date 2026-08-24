import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/maps/map_adapter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/search_models.dart';

/// Map view of search results.
///
/// This is the map counterpart to the list view. It uses the existing
/// [MapAdapter] abstraction so the real map provider (Google Maps,
/// Mapbox, OSM) can be swapped in later without touching the UI.
///
/// Currently renders a visual placeholder with markers for each shop that
/// has coordinates. When a real map provider is wired via
/// [mapAdapterProvider], this widget will render the interactive map.
class SearchResultsMapView extends ConsumerWidget {
  final List<ShopProductResult> results;
  final ValueChanged<ShopProductResult>? onResultTap;

  const SearchResultsMapView({
    super.key,
    required this.results,
    this.onResultTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only results with coordinates can be placed on a map.
    final mappable = results.where((r) => r.hasCoordinates).toList();

    if (mappable.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 64, color: AppColors.textMuted),
            SizedBox(height: AppSpacing.md),
            Text(
              'No shop locations available to show on map',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    final adapter = ref.watch(mapAdapterProvider);

    return Stack(
      children: [
        // Use the map adapter to render the map. Since the current stub
        // only supports a single destination, we pass the nearest result.
        Positioned.fill(
          child: adapter.buildMap(
            userLat: mappable.first.shopLatitude ?? 0,
            userLng: mappable.first.shopLongitude ?? 0,
            destLat: mappable.first.shopLatitude ?? 0,
            destLng: mappable.first.shopLongitude ?? 0,
            destName: mappable.first.shopName,
          ),
        ),
        // Marker legend overlay
        Positioned(
          top: AppSpacing.md,
          left: AppSpacing.md,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_on, size: 16, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(
                  '${mappable.length} shops',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        // Bottom result list (peek) for quick switching back to list
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _ResultPeekBar(results: mappable, onResultTap: onResultTap),
        ),
      ],
    );
  }
}

class _ResultPeekBar extends StatelessWidget {
  final List<ShopProductResult> results;
  final ValueChanged<ShopProductResult>? onResultTap;

  const _ResultPeekBar({required this.results, this.onResultTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      color: Theme.of(context).colorScheme.surface,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        itemCount: results.length.clamp(0, 4),
        itemBuilder: (context, index) {
          final result = results[index];
          return InkWell(
            onTap: () => onResultTap?.call(result),
            child: Container(
              width: 140,
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    result.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    result.shopName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${result.price.toStringAsFixed(0)} · ${result.distanceInKm.toStringAsFixed(1)} km',
                    style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}