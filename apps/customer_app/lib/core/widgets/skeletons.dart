import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_theme.dart';

/// The profile page's own silhouette, matching `_ProfileHeader`.
///
/// WHY A SEPARATE ONE AND NOT [SkeletonDetail]
/// -------------------------------------------
/// The profile page does not open with a banner — it opens with a centred 80px
/// avatar with a name and an email stacked under it, then a run of navigation
/// rows. Using the generic detail skeleton here would place a full-width banner
/// block where the avatar actually sits, so the content would jump a full
/// screen-height the moment the real header rendered. The whole point of a
/// skeleton is that the swap is invisible; that only holds if the placeholder
/// matches the thing it stands in for.
class SkeletonProfileHeader extends StatelessWidget {
  const SkeletonProfileHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SizedBox(height: AppSpacing.sm),
        // 80px diameter: `CircleAvatar(radius: 40)` in the real header.
        SkeletonBox(height: 80, width: 80, radius: 40),
        SizedBox(height: AppSpacing.md),
        // Name, then the email line under it.
        SkeletonBox(height: 20, width: 180),
        SizedBox(height: AppSpacing.sm),
        SkeletonBox(height: 14, width: 220),
      ],
    );
  }
}

/// A run of navigation `ListTile` rows — the profile page's account and legal
/// sections, and any other tile-driven list.
///
/// [SkeletonTileRow] already had this shape for the screens that name it
/// explicitly; this is the same silhouette exposed for callers that want to
/// draw a run of them next to their own header.
class SkeletonTileList extends StatelessWidget {
  /// How many rows to draw. Four fits a phone viewport without inviting a
  /// scroll through placeholders.
  final int rows;

  const SkeletonTileList({super.key, this.rows = 4});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows; i++) const SkeletonTileRow(),
      ],
    );
  }
}

/// A centred detail placeholder — the shape of a SINGLE record page (shop,
/// product, profile, order).
///
/// WHY THIS EXISTS
/// ---------------
/// `SkeletonRowShape` covers lists, and every list screen had already been
/// converted. The single-record pages were the gap: each one argued in a
/// comment that "a skeleton would promise rows this page does not have" and so
/// kept a bare centred spinner.
///
/// That reasoning was half right. A *row list* would be a lie for a shop page,
/// but the page's SHAPE is not unknowable — a shop has a banner, a name, a
/// rating, an address, a CTA. A spinner throws all of that away and then makes
/// the customer watch the real layout assemble from nothing when it lands.
/// [SkeletonDetail] draws that same silhouette as grey blocks, so the swap is
/// invisible instead of a full-screen re-layout.
///
/// Same honesty rule as the row skeletons: grey blocks of the right SHAPE, no
/// invented text, no invented prices, no invented ratings.
class SkeletonDetail extends StatelessWidget {
  /// Optional fixed-height block at the top, for the banner/cover image a
  /// detail page opens with (shop header, product photo). Null omits it.
  final double? headerHeight;

  const SkeletonDetail({super.key, this.headerHeight});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (headerHeight != null) ...[
            SkeletonBox(height: headerHeight!, radius: 10),
            const SizedBox(height: AppSpacing.md),
          ],
          // Title + the shorter second line under it.
          const SkeletonBox(height: 20, width: 220),
          const SizedBox(height: AppSpacing.sm),
          const SkeletonBox(height: 14, width: 140),
          const SizedBox(height: AppSpacing.lg),
          // A rating / meta row: one circle plus two short lines beside it.
          const Row(
            children: [
              SkeletonBox(height: 16, width: 16, radius: 8),
              SizedBox(width: AppSpacing.sm),
              SkeletonBox(height: 12, width: 70),
              SizedBox(width: AppSpacing.md),
              SkeletonBox(height: 12, width: 90),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // Body copy: three lines of varying width, because equal-width lines
          // read as a table, not as text.
          const SkeletonBox(height: 12),
          const SizedBox(height: AppSpacing.sm),
          const SkeletonBox(height: 12, width: 260),
          const SizedBox(height: AppSpacing.sm),
          const SkeletonBox(height: 12),
          const SizedBox(height: AppSpacing.lg),
          // A wide action block where a "primary CTA" row will land.
          const SkeletonBox(height: 48, radius: 8),
        ],
      ),
    );
  }
}

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

/// A circular leading block — the shape a `CircleAvatar` occupies in a
/// `ListTile` row (notifications, addresses).
class SkeletonCircle extends StatelessWidget {
  final double size;

  const SkeletonCircle({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) =>
      SkeletonBox(width: size, height: size, radius: size / 2);
}

/// A row shaped like a `ListTile`: circular leading, two text lines, trailing
/// block.
///
/// NOT interchangeable with [SkeletonCardRow], and using that one here is a
/// mistake the customer can see: a notification has no product photo and its row
/// is far shorter, so a card skeleton there makes the list jump when it lands
/// and promises an image that will never arrive.
class SkeletonTileRow extends StatelessWidget {
  final double height;

  const SkeletonTileRow({super.key, this.height = 72});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          children: [
            SkeletonCircle(),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(height: 14),
                  SizedBox(height: 6),
                  SkeletonBox(height: 12, width: 200),
                ],
              ),
            ),
            SizedBox(width: AppSpacing.sm),
            SkeletonBox(height: 12, width: 44),
          ],
        ),
      ),
    );
  }
}

/// A row shaped like the saved / recently viewed lists: a `Card` wrapping a
/// `ListTile` whose leading image is a small rounded SQUARE, with a title, a
/// subtitle, and a trailing delete button.
///
/// Distinct from [SkeletonTileRow] (circular leading — notifications,
/// addresses) and from [SkeletonCardRow] (large 64px photo, three lines —
/// search results). Those two lists genuinely differ in leading shape and line
/// count, so a single generic row for both would mispredict one of them.
class SkeletonMediaTileRow extends StatelessWidget {
  final double height;

  const SkeletonMediaTileRow({super.key, this.height = 76});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          SkeletonBox(width: 52, height: 52, radius: 8),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 14),
                SizedBox(height: 8),
                SkeletonBox(height: 12, width: 150),
              ],
            ),
          ),
          SizedBox(width: AppSpacing.sm),
          SkeletonBox(width: 24, height: 24, radius: 12),
        ],
      ),
    );
  }
}

/// A row shaped like an order card: order number and status pill on one line,
/// a date line, then a total line — and deliberately NO image, because an order
/// card has none.
class SkeletonOrderRow extends StatelessWidget {
  final double height;

  const SkeletonOrderRow({super.key, this.height = 116});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonBox(height: 16, width: 120),
              Spacer(),
              SkeletonBox(height: 20, width: 72, radius: 10),
            ],
          ),
          SizedBox(height: 10),
          SkeletonBox(height: 12, width: 160),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(height: 12, width: 200),
          SizedBox(height: 10),
          SkeletonBox(height: 14, width: 90),
        ],
      ),
    );
  }
}

/// One text line and a trailing icon slot — the shape of a search-history entry.
///
/// The shortest row in the app. A 96px card skeleton in this tab would imply
/// three lines of metadata per query, and the tab would visibly grow when the
/// real rows landed.
class SkeletonHistoryRow extends StatelessWidget {
  final double height;

  const SkeletonHistoryRow({super.key, this.height = 56});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          children: [
            SkeletonCircle(size: 24),
            SizedBox(width: AppSpacing.md),
            Expanded(child: SkeletonBox(height: 14)),
            SkeletonBox(width: 20, height: 20, radius: 4),
          ],
        ),
      ),
    );
  }
}

/// A row shaped like a support report: reference plus status chip, then two
/// lines of description.
class SkeletonIssueRow extends StatelessWidget {
  final double height;

  const SkeletonIssueRow({super.key, this.height = 120});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonBox(height: 13, width: 90),
              Spacer(),
              SkeletonBox(height: 20, width: 64, radius: 10),
            ],
          ),
          SizedBox(height: 12),
          SkeletonBox(height: 15),
          SizedBox(height: 8),
          SkeletonBox(height: 12, width: 240),
        ],
      ),
    );
  }
}

/// The real row shapes a list can be standing in for.
///
/// This enum exists because "a list" is not a shape. One generic card skeleton
/// was being used for every list in the app, so a notification list shimmered
/// product photos, an order list shimmered nothing where its status pill goes,
/// and search history reserved three lines per query it only uses one of. Each
/// screen now names the shape its rows actually have.
enum SkeletonRowShape {
  /// Image + text: search results, saved products, favourites, recently viewed,
  /// pin search, nearby shops.
  product,

  /// `ListTile` with a small rounded-square image, title, subtitle and a
  /// trailing delete: saved items, favourites, recently viewed.
  mediaTile,

  /// `ListTile` with a CIRCULAR leading: notifications, addresses.
  tile,

  /// Order card: number + status pill + date + total.
  order,

  /// One line + a trailing icon: search history.
  history,

  /// Report card: reference + chip + description.
  issue;

  /// The row height the real content uses for this shape, so the placeholder and
  /// the loaded list are the same size and the layout does not jump.
  double get rowHeight => switch (this) {
    product => 96,
    mediaTile => 76,
    tile => 76,
    order => 116,
    history => 56,
    issue => 120,
  };

  /// The gap between rows, matching how each real list separates its rows:
  /// card lists use a gap, `ListTile` lists use a hairline divider.
  double get separatorHeight => switch (this) {
    product => 10,
    mediaTile => AppSpacing.md,
    tile => 1,
    order => 10,
    history => 1,
    issue => 10,
  };
}

/// The rows [SkeletonRowShape.product] stands in for — the shape of a product or
/// shop card with a leading photo.
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

  /// Overrides the row height [SkeletonRowShape] would use. Null for almost every
  /// caller: the shape already knows its own height, and hard-coding a number at
  /// each call site is how a list ends up not matching itself.
  final double? rowHeight;

  /// The shape the rows will actually have. Defaults to
  /// [SkeletonRowShape.product] because that is what most lists are, but any
  /// screen whose rows are not product cards must say so — the whole point of a
  /// skeleton is that it is the right shape.
  final SkeletonRowShape shape;

  const SkeletonList({
    super.key,
    this.itemCount = 4,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.rowHeight,
    this.shape = SkeletonRowShape.product,
  });

  /// The height this list's rows are drawn at.
  double get height => rowHeight ?? shape.rowHeight;

  /// Builds one placeholder row for [shape]. The row's own height carries the
  /// layout, so an explicit [rowHeight] overrides only this row's height.
  Widget _row() => switch (shape) {
    SkeletonRowShape.product => SkeletonCardRow(height: height),
    SkeletonRowShape.mediaTile => SkeletonMediaTileRow(height: height),
    SkeletonRowShape.tile => SkeletonTileRow(height: height),
    SkeletonRowShape.order => SkeletonOrderRow(height: height),
    SkeletonRowShape.history => SkeletonHistoryRow(height: height),
    SkeletonRowShape.issue => SkeletonIssueRow(height: height),
  };

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
            separatorBuilder: (_, _) =>
                SizedBox(height: shape.separatorHeight),
            itemBuilder: (_, _) => _row(),
          ),
        ),
      ),
    );
  }
}
