import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/product_details_providers.dart';
import '../../../../features/customer/presentation/controllers/customer_controller.dart';
import '../../domain/models/product_details_models.dart';
import '../../../../core/network/api_error_handler.dart';
import '../../../../core/share/share_content.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/empty_state_view.dart';
import '../../../../core/widgets/product_share.dart';
import '../../../../core/widgets/slow_load_notice.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../../core/widgets/stale_data_notice.dart';
import '../widgets/product_image_gallery.dart';
import '../widgets/product_master_section.dart';
import '../widgets/product_offers_section.dart';
import '../widgets/product_price_summary.dart';
import '../widgets/price_comparison_section.dart';
import '../widgets/shop_inventory_section.dart';

/// Product Details screen.
///
/// The screen is split into two clearly-separated sections:
///   1. **PRODUCT INFORMATION** — global Product Master (static data)
///   2. **SHOP INVENTORY INFORMATION** — shop-specific availability (dynamic)
///
/// Navigation flow: Product → Nearby Shops → Shop → Directions
class ProductDetailsScreen extends ConsumerWidget {
  final String productId;
  const ProductDetailsScreen({super.key, required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productAsync = ref.watch(productDetailsProvider(productId));
    final isSaved = ref.watch(productIsSavedProvider(productId));

    // Phase 17 — record this view so the customer's "Recently Viewed" feed
    // stays in sync with the backend (fire-and-forget; never blocks the UI).
    ref.listen(productDetailsProvider(productId), (previous, next) {
      final pid = int.tryParse(productId);
      if (next.hasValue && pid != null) {
        ref.read(recordRecentViewProvider(RecentViewRequest(pid)));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Details'),
        actions: [
          productAsync.maybeWhen(
            data: (details) => IconButton(
              icon: Icon(
                isSaved ? Icons.bookmark : Icons.bookmark_border,
                color: isSaved ? AppColors.primary : null,
              ),
              tooltip: isSaved ? 'Remove from saved' : 'Save product',
              onPressed: () {
                ref.read(productIsSavedProvider(productId).notifier).toggle();
              },
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share product',
            onPressed: () {
              final details = productAsync.value;
              if (details == null) return;
              final master = details.product;
              // The EAN/UPC is preferred for the link over the internal
              // product id: it is printed on the box, so sharing it reveals
              // nothing a customer was not already holding.
              final identifiers = [
                for (final id in master.identifiers)
                  (type: id.type, value: id.value),
              ];
              shareProductContent(
                ref,
                buildProductShareContent(
                  productName: master.name,
                  brand: master.brand,
                  productId: master.id,
                  identifiers: identifiers,
                ),
              );
            },
          ),
        ],
      ),
      body: productAsync.when(
        data: (details) => _buildBody(context, ref, details),
        loading: () => _ProductLoadingView(
          onRetry: () => ref.refresh(productDetailsProvider(productId)),
        ),
        error: (err, stack) => _ProductErrorView(
          error: err,
          onRetry: () => ref.refresh(productDetailsProvider(productId)),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    ProductDetails details,
  ) {
    return RefreshIndicator(
      onRefresh: () => ref.refresh(productDetailsProvider(productId).future),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── OFFLINE / STALE DISCLOSURE ───────────────────────────────
            // Must come first so it is impossible to miss: everything below
            // this line may be a cached snapshot rather than live data. The
            // spec forbids presenting cached content as live, and a notice
            // buried under a product image is functionally absent.
            if (details.servedFromCache)
              StaleDataNotice(
                label: details.lastUpdatedLabel,
                onRetry: () => ref.refresh(productDetailsProvider(productId)),
              ),

            // ── PRODUCT IMAGE ────────────────────────────────────────────
            ProductImageGallery(imageUrls: details.product.imageUrls),

            // ── CURRENT PRICE / AVAILABILITY / FRESHNESS AT A GLANCE ─────
            ProductPriceSummary(details: details),

            // ── SECTION: PRODUCT INFORMATION (global static info) ────────
            ProductMasterSection(product: details.product),

            const Divider(height: 1),

            // ── SECTION: AVAILABLE NEARBY SHOPS (dynamic availability) ───
            // Fed `liveOffers`, not `shopOffers`: for cached data this is
            // empty, so the section renders its honest "cannot confirm
            // availability" message instead of stale "In Stock" tiles.
            ShopInventorySection(
              productId: productId,
              offers: details.liveOffers,
              unverified: !details.hasLiveShopData,
            ),

            // ── SECTION: PRICE COMPARISON ────────────────────────────────
            if (details.liveOffers.length > 1) ...const [Divider(height: 1)],
            PriceComparisonSection(
              details: details,
              onShopTap: (offer) => context.push('/shop/${offer.shopId}'),
            ),

            // ── SECTION: OFFERS ──────────────────────────────────────────
            if (details.offersWithDeals.isNotEmpty) ...const [
              Divider(height: 1),
            ],
            ProductOffersSection(
              details: details,
              onShopTap: (offer) => context.push('/shop/${offer.shopId}'),
            ),

            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

/// Loading state with skeleton-style placeholders.
///
/// The image placeholder still shows a spinner while the rest of the page
/// shimmers, because a photograph is a single thing waiting to arrive and a
/// block of grey is exactly its shape. [onRetry] bounds the wait: past the
/// threshold the customer is told it is slow and offered a real re-read rather
/// than an indefinite spinner over a grey rectangle.
class _ProductLoadingView extends StatelessWidget {
  final VoidCallback? onRetry;

  const _ProductLoadingView({this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      children: [
        // Image placeholder. A SHIMMERING BLOCK, not a spinner on a grey rectangle:
        // the spinner said "fetching" while sitting inside a box that already
        // looked like the photo's final position, so the two layers fought each
        // other. A shimmer block is one honest shape for one arriving photo.
        const SkeletonBox(height: 240, radius: 0),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 80,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: 200,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                width: 120,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                width: double.infinity,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                width: double.infinity,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ),
        ),
        SlowLoadNotice(
          message: 'This product is taking longer to load.',
          onRetry: onRetry,
        ),
      ],
    );
  }
}

/// Error state with retry.
class _ProductErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _ProductErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      icon: Icons.error_outline,
      title: 'Failed to load product details',
      // User-safe copy only; raw exception text never reaches the UI.
      message: friendlyErrorMessage(error),
      actionLabel: 'Try Again',
      onActionTap: onRetry,
    );
  }
}
