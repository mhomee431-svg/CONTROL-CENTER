import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/responsive.dart';
import '../../../../core/widgets/product_card.dart';
import '../../../../core/widgets/section_header.dart';
import '../../domain/models/home_data.dart';

/// Reusable horizontal product row used for popular, recently viewed,
/// and recommended product sections. Hides itself when empty.
class ProductRowSection extends StatelessWidget {
  final String title;
  final List<Product> products;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  const ProductRowSection({
    super.key,
    required this.title,
    required this.products,
    this.actionLabel,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          actionLabel: actionLabel,
          onActionTap: onActionTap,
        ),
        // Responsive: the rail grows with the customer's font size.
        //
        // `ProductCard` carries a product name, a price and a shop name, all of
        // which scale with the system text size. A fixed 240 meant the card grew
        // while the rail did not, and the row overflowed for anyone running a
        // large accessibility font -- the same failure as
        // `nearby_shops_section`, which is why both use the same helper.
        LayoutBuilder(
          builder: (context, constraints) {
            return SizedBox(
              height: Responsive.carouselHeight(
                baseHeight: 240,
                textScale: MediaQuery.textScalerOf(context),
              ),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(
                  horizontal: Responsive.gutterFor(constraints.maxWidth),
                ),
                itemCount: products.length,
                itemBuilder: (context, index) {
                  final product = products[index];
                  return ProductCard(
                    product: product,
                    onTap: () => context.push('/product/${product.id}'),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}
