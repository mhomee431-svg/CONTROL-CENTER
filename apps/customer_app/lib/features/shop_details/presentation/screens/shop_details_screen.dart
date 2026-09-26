import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/shop_details_controller.dart';
import '../../domain/models/shop_details_models.dart';
import '../widgets/shop_header.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/network_image_view.dart';
import '../../../../core/widgets/empty_state_view.dart';
import '../../../auth/presentation/widgets/auth_gate_sheet.dart';

class ShopDetailsScreen extends ConsumerWidget {
  final String shopId;
  const ShopDetailsScreen({super.key, required this.shopId});

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _shareShop(ShopProfile shop) async {
    final text =
        'Check out ${shop.name} on Hyperlocal!\n'
        '${shop.address}\n'
        'Rating: ${shop.rating} (${shop.reviewCount} reviews)';
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _openDirections(
    BuildContext context,
    WidgetRef ref,
    ShopProfile shop,
  ) async {
    final allowed = await requireAuthentication(
      context,
      ref,
      actionLabel: 'get directions to this shop',
    );
    if (!allowed || !context.mounted) return;
    context.push(
      '/directions?shopId=${shop.id}&name=${Uri.encodeComponent(shop.name)}',
    );
  }

  Future<void> _callShop(
    BuildContext context,
    WidgetRef ref,
    String phone,
  ) async {
    final allowed = await requireAuthentication(
      context,
      ref,
      actionLabel: 'call this shop',
    );
    if (!allowed || !context.mounted) return;
    await _launchUrl('tel:$phone');
  }

  Future<void> _guardedLaunch(
    BuildContext context,
    WidgetRef ref,
    String url,
    String actionLabel,
  ) async {
    final allowed = await requireAuthentication(
      context,
      ref,
      actionLabel: actionLabel,
    );
    if (!allowed || !context.mounted) return;
    await _launchUrl(url);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shopAsync = ref.watch(shopDetailsProvider(shopId));
    final isSaved = ref.watch(shopIsSavedProvider(shopId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shop Profile'),
        actions: [
          shopAsync.maybeWhen(
            data: (shop) => IconButton(
              icon: Icon(
                isSaved ? Icons.favorite : Icons.favorite_border,
                color: AppColors.error,
              ),
              tooltip: isSaved ? 'Remove from favorites' : 'Save shop',
              onPressed: () {
                ref.read(shopIsSavedProvider(shopId).notifier).toggle();
              },
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          shopAsync.maybeWhen(
            data: (shop) => IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share shop',
              onPressed: () => _shareShop(shop),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: shopAsync.when(
        data: (shop) => _buildBody(context, ref, shop),
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.store_outlined,
                size: 64,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Unable to load shop\nPlease try again.',
                textAlign: TextAlign.center,
              ),
              TextButton(
                onPressed: () => ref.refresh(shopDetailsProvider(shopId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, ShopProfile shop) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShopHeader(shop: shop),

          // ACTION BUTTONS
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: shop.phone.isNotEmpty
                        ? () => _callShop(context, ref, shop.phone)
                        : null,
                    icon: const Icon(Icons.call),
                    label: const Text('Call'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openDirections(context, ref, shop),
                    icon: const Icon(Icons.directions),
                    label: const Text('Directions'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 32),

          // INFO SECTION
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildContactSection(context, ref, shop),
                const SizedBox(height: AppSpacing.lg),

                _buildSectionTitle('Operating Hours'),
                Text(
                  shop.openingHours,
                  style: const TextStyle(color: AppColors.textMuted),
                ),
                if (!shop.isOpenNow) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'This shop is currently closed. Check opening hours before you visit.',
                      style: TextStyle(fontSize: 12, color: AppColors.error),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),

                if (shop.activeOffers.isNotEmpty) ...[
                  _buildSectionTitle('Shop Offers'),
                  ...shop.activeOffers.map(
                    (offer) => Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.local_offer,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              offer,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],

                _buildSectionTitle('About Shop'),
                Text(
                  shop.about,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // INVENTORY FRESHNESS
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.update,
                        size: 20,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Inventory last updated ${DateTime.now().difference(shop.lastInventoryUpdate).inHours} hours ago',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // SHOP COORDINATES UNAVAILABLE WARNING
                if (!shop.hasValidCoordinates)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      border: Border.all(color: Colors.orange.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.location_off,
                          size: 20,
                          color: Colors.orange,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Shop coordinates are temporarily unavailable. You can still call the shop for directions.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // INVENTORY GRID
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle('Available Products'),
                const SizedBox(height: AppSpacing.sm),
                if (shop.availableProducts.isEmpty)
                  const EmptyStateView(
                    icon: Icons.inventory_2_outlined,
                    title: 'No products available',
                    message: 'This shop has no products listed right now.',
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.75,
                          crossAxisSpacing: AppSpacing.md,
                          mainAxisSpacing: AppSpacing.md,
                        ),
                    itemCount: shop.availableProducts.length,
                    itemBuilder: (context, index) {
                      final product = shop.availableProducts[index];
                      return _ProductSummaryCard(product: product);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactSection(
    BuildContext context,
    WidgetRef ref,
    ShopProfile shop,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Contact'),
        if (shop.phone.isNotEmpty)
          _buildContactRow(
            icon: Icons.call_outlined,
            text: shop.phone,
            onTap: () => _guardedLaunch(
              context,
              ref,
              'tel:${shop.phone}',
              'call this shop',
            ),
          ),
        if (shop.secondaryPhone.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _buildContactRow(
            icon: Icons.phone_android_outlined,
            text: shop.secondaryPhone,
            onTap: () => _guardedLaunch(
              context,
              ref,
              'tel:${shop.secondaryPhone}',
              'call this shop',
            ),
          ),
        ],
        if (shop.email.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _buildContactRow(
            icon: Icons.email_outlined,
            text: shop.email,
            onTap: () => _guardedLaunch(
              context,
              ref,
              'mailto:${shop.email}',
              'email this shop',
            ),
          ),
        ],
        if (shop.phone.isEmpty &&
            shop.secondaryPhone.isEmpty &&
            shop.email.isEmpty)
          const Text(
            'No contact info available',
            style: TextStyle(color: AppColors.textMuted),
          ),
      ],
    );
  }

  Widget _buildContactRow({
    required IconData icon,
    required String text,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
            if (onTap != null)
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.textMuted,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _ProductSummaryCard extends StatelessWidget {
  final ShopProductSummary product;
  const _ProductSummaryCard({required this.product});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(
        '/product/${product.productId}',
      ), // Navigation -> Product Profile
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: NetworkImageView(
                imageUrl: product.imageUrl,
                width: double.infinity,
                borderRadius: 12,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${product.price.toInt()}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product.isAvailable ? 'In Stock' : 'Out of Stock',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: product.isAvailable
                          ? AppColors.secondary
                          : AppColors.error,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
