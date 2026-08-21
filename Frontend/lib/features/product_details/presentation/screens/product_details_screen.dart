import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/product_details_providers.dart';
import '../../domain/models/product_details_models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/network_image_view.dart';

class ProductDetailsScreen extends ConsumerWidget {
  final String productId;
  const ProductDetailsScreen({super.key, required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productAsync = ref.watch(productDetailsProvider(productId));
    final isSaved = ref.watch(productIsSavedProvider(productId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Details'),
        actions: [
          productAsync.maybeWhen(
            data: (product) => IconButton(
              icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border, color: AppColors.primary),
              onPressed: () {
                ref.read(productIsSavedProvider(productId).notifier).toggle();
              },
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => SharePlus.instance.share(
              ShareParams(text: 'Check out this product on Hyperlocal! ID: $productId'),
            ),
          ),
        ],
      ),
      body: productAsync.when(
        data: (product) => _buildBody(context, product),
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (err, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: AppColors.textMuted),
                const SizedBox(height: 16),
                Text(
                  'Failed to load product details',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '$err',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => ref.refresh(productDetailsProvider(productId)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ProductDetails product) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image Carousel / Header
          SizedBox(
            height: 240,
            child: PageView.builder(
              itemCount: product.imageUrls.length,
              itemBuilder: (context, index) {
                return NetworkImageView(imageUrl: product.imageUrls[index], borderRadius: 0);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.brand.toUpperCase(), style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(product.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: AppSpacing.sm),
                Text(product.priceRange, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
                const SizedBox(height: AppSpacing.md),
                const Text('Description', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(product.description, style: const TextStyle(color: AppColors.textMuted, height: 1.4)),
                const SizedBox(height: AppSpacing.lg),
                const Divider(),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Available at Nearby Shops', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('${product.nearbyShopsOffers.length} found', style: const TextStyle(color: AppColors.textMuted)),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                ...product.nearbyShopsOffers.map((offer) => _ShopOfferCard(offer: offer)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShopOfferCard extends StatelessWidget {
  final ShopOffer offer;
  const _ShopOfferCard({required this.offer});

  String _formatFreshness(DateTime lastUpdated) {
    final diff = DateTime.now().difference(lastUpdated);
    if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes} mins ago';
    if (diff.inHours < 24) return 'Updated ${diff.inHours} hours ago';
    return 'Updated ${diff.inDays} days ago (Stale)';
  }

  bool _isStale(DateTime lastUpdated) {
    return DateTime.now().difference(lastUpdated).inHours > 24;
  }

  @override
  Widget build(BuildContext context) {
    final stale = _isStale(offer.lastUpdated);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: offer.isAvailable ? Colors.grey.shade300 : AppColors.error.withValues(alpha: 0.4)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              NetworkImageView(imageUrl: offer.shopImageUrl, width: 48, height: 48, borderRadius: 8),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(offer.shopName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text('${offer.distanceInKm} km away • ⭐ ${offer.rating}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('₹${offer.price.toInt()}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: offer.isAvailable ? AppColors.secondary.withValues(alpha: 0.1) : AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      offer.isAvailable ? 'In Stock' : 'Out of Stock',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: offer.isAvailable ? AppColors.secondary : AppColors.error),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (offer.offerText != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
              child: Row(
                children: [
                  const Icon(Icons.local_offer, size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(offer.offerText!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.primary)),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.access_time, size: 13, color: stale ? AppColors.error : AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    _formatFreshness(offer.lastUpdated),
                    style: TextStyle(fontSize: 11, color: stale ? AppColors.error : AppColors.textMuted, fontWeight: stale ? FontWeight.bold : FontWeight.normal),
                  ),
                ],
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => context.push('/shop/${offer.shopId}'),
                    icon: const Icon(Icons.storefront, size: 16),
                    label: const Text('View Shop', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 4),
                  ElevatedButton.icon(
                    onPressed: () => context.push('/directions?shopId=${offer.shopId}'),
                    icon: const Icon(Icons.directions, size: 16),
                    label: const Text('Directions', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}