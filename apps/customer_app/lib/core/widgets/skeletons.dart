import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_theme.dart';

/// Shimmer skeletons for list-shaped content.
///
/// WHY SKELETONS AND NOT A SPINNER
/// -------------------------------
/// A centred spinner says "wait" and nothing else. A skeleton of the content
/// that is arriving says what is arriving, and it lets the layout settle before
/// the data lands — so the list does not jump under the customer's thumb the
/// moment results appear. The home feed already used this (`HomeSkeletonLoader`);
/// this file is the same idea for a LIST of cards, which is what search results,
/// saved items and orders all are.
///
/// The widgets here render NO text and NO numbers: a skeleton that invented
/// "₹0" or a shop name would be asserting data before the data exists. Only
/// grey blocks of the right SHAPE, which is the one thing that is certain.

/// One rounded shimmer block. [width] may be null to fill the available space.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        // The colour is only the SHAPE's base; [Shimmer.fromColors] repaints it.
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A card-shaped skeleton row: leading image block, two text lines, trailing
/// block — the silhouette of a result/saved/order row.
class SkeletonCardRow extends StatelessWidget {
  final double height;
  const SkeletonCardRow({super.key, this.height = 96});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 64, height: 64, radius: 8),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 14),
                SizedBox(height: 8),
                SkeletonBox(height: 12, width: 140),
                SizedBox(height: 8),
                SkeletonBox(height: 12, width: 90),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A non-scrolling list of card skeletons, wrapped in one shimmer.
///
/// `IgnorePointer` + `Semantics(excludeSemantics: true)`: a skeleton is
/// decoration. A screen reader announcing "unlabeled box" twelve times, or a
/// customer tapping a placeholder row, are both failures of the same idea —
/// a skeleton must not claim to be content.
class SkeletonList extends StatelessWidget {
  final int itemCount;
  final EdgeInsetsGeometry padding;
  final double rowHeight;

  const SkeletonList({
    super.key,
    this.itemCount = 4,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.rowHeight = 96,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      excludeSemantics: true,
      child: IgnorePointer(
        child: Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: ListView.separated(
            padding: padding,
            // Never scrollable: a skeleton is a still image of a layout, and a
            // customer scrolling placeholders has been given nothing.
            physics: const NeverScrollableScrollPhysics(),
            itemCount: itemCount,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, _) => SkeletonCardRow(height: rowHeight),
          ),
        ),
      ),
    );
  }
}
