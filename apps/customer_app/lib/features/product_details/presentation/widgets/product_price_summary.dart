import 'package:flutter/material.dart';

import '../../domain/models/product_details_models.dart';
import '../../../search/domain/models/search_models.dart';
import '../../../../core/theme/app_theme.dart';

/// The at-a-glance answer strip under the product header.
///
/// Reports the facts a customer needs before scrolling: the current price (the
/// lowest one actually in stock), whether anything is available nearby, and how
/// old that stock reading is.
///
/// Deliberately conservative:
/// * With no in-stock offer there is no "current price" and the strip says so
///   rather than falling back to MRP, which would misrepresent the price.
/// * The price is the lowest *reported* price, never a promise.
class ProductPriceSummary extends StatelessWidget {
  final ProductDetails details;

  const ProductPriceSummary({super.key, required this.details});

  @override
  Widget build(BuildContext context) {
    // `liveOffers` is empty for cached payloads, so every derived figure below
    // (lowest price, in-stock count, freshness) is null/0 rather than a
    // remembered value. That is the point: no number here can be read as a
    // current claim when the underlying data is stale.
    final offers = details.liveOffers;
    final inStock = offers.where((o) => !o.isOutOfStock).toList();
    final lowest = details.lowestPrice;
    final mrp = details.product.mrp;

    // Freshest reading among in-stock shops drives the summary freshness line:
    // the best evidence available about how current this stock data is.
    DateTime? newest;
    String? newestStatus;
    for (final o in inStock) {
      if (newest == null || o.lastUpdated.isAfter(newest)) {
        newest = o.lastUpdated;
        newestStatus = o.freshnessStatus;
      }
    }
    final freshnessLabel = inStock.isEmpty
        ? null
        : formatFreshnessText(newest, backendStatus: newestStatus);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      color: AppColors.primary.withValues(alpha: 0.04),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.xs),
          _PriceLine(lowest: lowest, mrp: mrp),
          const SizedBox(height: 4),
          _AvailabilityLine(
            inStockCount: inStock.length,
            unverified: !details.hasLiveShopData,
          ),
          if (freshnessLabel != null) ...[
            const SizedBox(height: 3),
            _FreshnessLine(label: freshnessLabel),
          ],
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }
}


/// The current price, or an honest "no current price" when nothing is in stock.
class _PriceLine extends StatelessWidget {
  final double? lowest;
  final double? mrp;

  const _PriceLine({required this.lowest, required this.mrp});

  @override
  Widget build(BuildContext context) {
    final hasLive = lowest != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (hasLive) ...[
          Text(
            '₹${lowest!.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 6),
          const Padding(
            padding: EdgeInsets.only(bottom: 3),
            child: Text(
              'current price',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
          // Master MRP shown for reference only when it actually differs.
          if (mrp != null && mrp! > lowest!) ...[
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                'MRP ₹${mrp!.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            ),
          ],
        ] else ...[
          // No live offer — say so instead of presenting MRP as the current
          // price, which would misrepresent what the customer would pay.
          const Text(
            'No current price',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textMuted,
            ),
          ),
          if (mrp != null) ...[
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                'MRP ₹${mrp!.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// How many nearby shops currently report this item in stock.
class _AvailabilityLine extends StatelessWidget {
  final int inStockCount;

  /// True when the underlying shop data came from cache and so supports no
  /// claim at all — not even a negative one.
  final bool unverified;

  const _AvailabilityLine({required this.inStockCount, this.unverified = false});

  @override
  Widget build(BuildContext context) {
    // The distinction that matters: "we checked and nobody has it" is a real
    // answer, but "we have no current data" is not. Reporting the latter as
    // the former would tell a customer to go elsewhere on the strength of a
    // cache entry that may be days old.
    final none = inStockCount == 0;
    final unknown = unverified;

    final (label, color) = unknown
        ? ('Availability not confirmed — connect to refresh', AppColors.textMuted)
        : none
        ? ('Not reported in stock at any nearby shop', AppColors.error)
        : (
            'In stock at $inStockCount nearby ${inStockCount == 1 ? 'shop' : 'shops'}',
            AppColors.textMuted,
          );

    return Row(
      children: [
        Icon(
          unknown
              ? Icons.help_outline
              : none
              ? Icons.cancel_outlined
              : Icons.storefront,
          size: 14,
          color: unknown ? AppColors.textMuted : (none ? AppColors.error : AppColors.secondary),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ),
      ],
    );
  }
}

/// How old the freshest stock reading is, using the shared formatter.
class _FreshnessLine extends StatelessWidget {
  final String label;

  const _FreshnessLine({required this.label});

  @override
  Widget build(BuildContext context) {
    final warn = isFreshnessWarning(label);
    final color = warn ? AppColors.error : AppColors.textMuted;

    return Row(
      children: [
        Icon(Icons.access_time, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}
