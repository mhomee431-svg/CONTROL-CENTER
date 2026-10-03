import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/shop_details_controller.dart';
import '../controllers/business_profile_controller.dart';
import '../controllers/transport_quote_controller.dart';
import '../../domain/models/business_profile_models.dart';
import '../../domain/models/shop_details_models.dart';
import '../../../../core/catalog/business_capability.dart';
import '../widgets/shop_header.dart';
import '../widgets/restaurant_menu_section.dart';
import '../widgets/request_quote_sheet.dart';
import '../widgets/service_profile_section.dart';
import '../../../../core/share/share_content.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/network_image_view.dart';
import '../../../../core/widgets/empty_state_view.dart';
import '../../../../core/widgets/slow_load_notice.dart';
import '../../../../core/widgets/product_share.dart';
import '../../../auth/presentation/widgets/auth_gate_sheet.dart';

class ShopDetailsScreen extends ConsumerWidget {
  final String shopId;
  const ShopDetailsScreen({super.key, required this.shopId});

  /// Phone numbers arrive display-formatted ("+91 98765 43210"); the `tel:`
  /// scheme accepts only digits and a leading `+`, so strip formatting before
  /// building the intent. Returns '' when nothing dialable remains.
  String _sanitizePhone(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    // Keep a single leading '+' at most — anything else is not dialable.
    if (cleaned.isEmpty || cleaned == '+') return '';
    final plusStripped = cleaned.replaceAll('+', '');
    return cleaned.startsWith('+') ? '+$plusStripped' : plusStripped;
  }

  Future<void> _launchUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (!await canLaunchUrl(uri)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this link right now.')),
      );
      return;
    }
    await launchUrl(uri);
  }

  Future<void> _shareShop(WidgetRef ref, ShopProfile shop) async {
    // Composed centrally so the shop id lands only in the link, never in the
    // text, and so a leak here is impossible by construction rather than by
    // remembering not to interpolate something.
    await shareProductContent(
      ref,
      buildShopShareContent(
        shopName: shop.name,
        address: shop.address,
        rating: shop.rating,
        reviewCount: shop.reviewCount,
        activeOfferCount: shop.activeOffers.length,
        categories: shop.categories,
        shopId: shop.id,
      ),
    );
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
    final dialable = _sanitizePhone(phone);
    if (dialable.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This phone number cannot be dialed.')),
      );
      return;
    }
    await _launchUrl(context, 'tel:$dialable');
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
    await _launchUrl(context, url);
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
              onPressed: () => _shareShop(ref, shop),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: shopAsync.when(
        data: (shop) => _buildBody(context, ref, shop),
        // ONE shop, not a list: a row skeleton would promise a list this page
        // does not have. The spinner is bounded and retryable.
        loading: () => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator.adaptive(),
              SlowLoadNotice(
                message: 'This shop is taking longer to load.',
                onRetry: () => ref.invalidate(shopDetailsProvider(shopId)),
              ),
            ],
          ),
        ),
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
    // Which surfaces exist is the backend's answer, not a client guess: a
    // restaurant gets a menu, a transport/travel provider gets its services and
    // (only where the contract exists) a quote request, and a product shop gets
    // the inventory grid. See Master Spec §86-§89.
    final capabilities = shop.effectiveCapabilities;

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
                if (shop.phone.isNotEmpty && shop.hasValidCoordinates)
                  const SizedBox(width: AppSpacing.md),
                // Directions stay hidden when the backend has no usable shop
                // coordinates — a button that opens a map error state would be
                // a dead action.
                if (shop.hasValidCoordinates)
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

          // INVENTORY GRID — ONLY for a business that actually sells products.
          //
          // Gated on the capability rather than on "is the list empty": a
          // restaurant or a transport provider with no products is not a shop
          // with an empty catalogue, and showing it the price/stock grid is
          // exactly the product-style UI §88 forbids on a service category.
          if (capabilities.supportsProductCatalog)
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

          // BUSINESS PROFILE — a restaurant's menu or a provider's services.
          if (capabilities.needsBusinessProfile)
            _buildBusinessProfileSection(context, ref, shop, capabilities),
        ],
      ),
    );
  }

  /// The restaurant's menu, or the provider's services + quote entry point.
  ///
  /// Loading and failure are both local to this section: a business profile that
  /// will not load must not take the identity content the customer is already
  /// reading (name, hours, contact, directions) down with it.
  Widget _buildBusinessProfileSection(
    BuildContext context,
    WidgetRef ref,
    ShopProfile shop,
    BusinessCapabilitySet capabilities,
  ) {
    final profileAsync = ref.watch(shopBusinessProfileProvider(shop.id));
    final title = capabilities.supportsMenu ? 'Menu' : 'Services';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(title),
          profileAsync.when(
            data: (profile) => switch (profile) {
              BusinessProfileRestaurant(:final restaurant) =>
                RestaurantMenuView(restaurant: restaurant),
              BusinessProfileService(:final service) => ServiceProfileSection(
                service: service,
                // A request entry point only where the backend contract for it
                // exists. Without the capability the services are shown and
                // no button appears — a booking form with nothing behind it
                // would be a faked booking.
                canRequestQuote: capabilities.supportsQuoteRequest,
                onRequestQuote: capabilities.supportsQuoteRequest
                    ? () => _openQuoteSheet(context, ref, service)
                    : null,
              ),
              // The capability is there but the record is not published yet, or
              // this business needs no extra surface: say so honestly instead
              // of showing an empty section.
              BusinessProfileNone() => Text(
                title == 'Menu'
                    ? 'This restaurant has not published a menu yet. Call '
                          'them for today\'s specials.'
                    : 'This provider has not published its services yet. '
                          'Call them for the latest options.',
                style: const TextStyle(color: AppColors.textMuted),
              ),
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator.adaptive(),
                ),
              ),
            ),
            error: (_, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Could not load this $title right now.',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
                TextButton(
                  onPressed: () =>
                      ref.invalidate(shopBusinessProfileProvider(shop.id)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the quote request sheet.
  ///
  /// The sheet resets the quote ViewModel on close so a previous outcome can
  /// never be the first thing a new request shows.
  Future<void> _openQuoteSheet(
    BuildContext context,
    WidgetRef ref,
    TransportServiceProfile service,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) =>
          RequestQuoteSheet(providerId: service.id, services: service.services),
    );
    ref.read(transportQuoteViewModelProvider.notifier).reset();
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
            onTap: () {
              final dialable = _sanitizePhone(shop.phone);
              if (dialable.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('This phone number cannot be dialed.'),
                  ),
                );
                return;
              }
              _guardedLaunch(context, ref, 'tel:$dialable', 'call this shop');
            },
          ),
        if (shop.secondaryPhone.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _buildContactRow(
            icon: Icons.phone_android_outlined,
            text: shop.secondaryPhone,
            onTap: () {
              final dialable = _sanitizePhone(shop.secondaryPhone);
              if (dialable.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('This phone number cannot be dialed.'),
                  ),
                );
                return;
              }
              _guardedLaunch(context, ref, 'tel:$dialable', 'call this shop');
            },
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
