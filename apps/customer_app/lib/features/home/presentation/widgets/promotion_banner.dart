import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/responsive.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/network_image_view.dart';
import '../../domain/models/home_data.dart';

/// Horizontal carousel of promotional/offer banners.
/// Backend-driven via [Promotion] list; hides itself when empty.
class PromotionBanner extends StatefulWidget {
  final List<Promotion> promotions;

  const PromotionBanner({super.key, required this.promotions});

  @override
  State<PromotionBanner> createState() => _PromotionBannerState();
}

class _PromotionBannerState extends State<PromotionBanner> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.promotions.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Latest Offers',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        // Responsive: the carousel grows with the customer's font size.
        //
        // `_PromotionCard` renders a headline plus body copy, both of which
        // scale with the system text size. The fixed 160 meant the promo text
        // grew while the page did not, and the card overflowed — or silently
        // clipped its offer — for anyone using a large accessibility font. A
        // promotion a customer cannot read is worse than no promotion, because
        // the price they acted on may be the one that was cut off.
        LayoutBuilder(
          builder: (context, constraints) {
            return SizedBox(
              height: Responsive.carouselHeight(
                baseHeight: 160,
                textScale: MediaQuery.textScalerOf(context),
              ),
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.promotions.length,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemBuilder: (context, index) {
                  final promo = widget.promotions[index];
                  return Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: Responsive.gutterFor(constraints.maxWidth),
                    ),
                    child: _PromotionCard(promotion: promo),
                  );
                },
              ),
            );
          },
        ),
        if (widget.promotions.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              widget.promotions.length,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _currentPage == index ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _currentPage == index
                      ? AppColors.primary
                      : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PromotionCard extends StatelessWidget {
  final Promotion promotion;

  const _PromotionCard({required this.promotion});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final target = promotion.ctaTarget;
        if (target != null && target.isNotEmpty) {
          context.push(target);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          NetworkImageView(imageUrl: promotion.imageUrl, borderRadius: 12),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.black.withValues(alpha: 0.55),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: AppSpacing.md,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  promotion.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  promotion.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                if (promotion.ctaLabel != null &&
                    promotion.ctaLabel!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      promotion.ctaLabel!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
