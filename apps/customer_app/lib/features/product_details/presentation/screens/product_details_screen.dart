import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/product_details_providers.dart';
import '../../../../features/customer/presentation/controllers/customer_controller.dart';
import '../../domain/models/product_details_models.dart';
import '../../../../core/network/api_error_handler.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/empty_state_view.dart';
import '../widgets/product_image_gallery.dart';
import '../widgets/product_master_section.dart';
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
        ref.read(recordRecentViewProvider(
          RecentViewRequest(pid),
        ));
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
              final name = productAsync.value?.product.name ?? 'this product';
              SharePlus.instance.share(
                ShareParams(
                  text: 'Check out $name on Hyperlocal!',
                  subject: 'Product: $name',
                ),
              );
            },
          ),
        ],
      ),
      body: productAsync.when(
        data: (details) => _buildBody(context, ref, details),
        loading: () => const _ProductLoadingView(),
        error: (err, stack) => _ProductErrorView(
          error: err,
          onRetry: () => ref.refresh(productDetailsProvider(productId)),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, ProductDetails details) {
    return RefreshIndicator(
      onRefresh: () => ref.refresh(productDetailsProvider(productId).future),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── PRODUCT MASTER (global static info) ──────────────────────
            ProductImageGallery(imageUrls: details.product.imageUrls),
            ProductMasterSection(product: details.product),

            const Divider(height: 1),

            // ── SHOP INVENTORY (dynamic availability) ────────────────────
            ShopInventorySection(
              productId: productId,
              offers: details.shopOffers,
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

/// Loading state with skeleton-style placeholders.
class _ProductLoadingView extends StatelessWidget {
  const _ProductLoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      children: [
        // Image placeholder
        Container(
          height: 240,
          color: Colors.grey.shade200,
          child: const Center(
            child: CircularProgressIndicator.adaptive(),
          ),
        ),
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