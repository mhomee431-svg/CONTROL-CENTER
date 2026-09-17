import 'package:flutter/material.dart';

/// How the rows of a [LazyListView] are grouped.
enum LazyListStyle {
  /// Plain rows, optionally separated by a divider — the app's inventory /
  /// price lists.
  plain,

  /// Rows inside ONE outlined card — the products list. The card's chrome is
  /// painted per row (see [LazyCardSliver]) so the group still reads as a single
  /// card while the rows stay lazily built.
  card,
}

/// A scrollable page whose rows are built lazily.
///
/// [header] and [footer] are small, eager blocks (summary chips, a search box,
/// an action row). The rows are NOT eager: `ListView(children: [...])`
/// constructs one widget per row on every rebuild, which is what makes a
/// 2,000-product list stutter on each keystroke — the filter is cheap, the
/// allocation storm after it is not. Here the row builder runs only for the rows
/// near the viewport, so typing costs the filter and nothing else.
///
/// One implementation serves every list screen: the products list (header +
/// lazy card rows), the inventory/price lists (lazy plain rows) and any future
/// paginated surface, so list behaviour — separators, padding, empty state —
/// cannot drift between features.
class LazyListView extends StatelessWidget {
  const LazyListView({
    super.key,
    this.header = const <Widget>[],
    this.footer = const <Widget>[],
    required this.itemCount,
    required this.itemBuilder,
    this.separatorBuilder,
    this.padding = EdgeInsets.zero,
    this.controller,
    this.physics,
    this.style = LazyListStyle.plain,
    this.emptyPlaceholder,
  });

  /// Eager blocks above the rows (they are few, and they must stay reachable
  /// while the list is empty).
  final List<Widget> header;

  /// Eager blocks below the rows (e.g. a trailing spacer).
  final List<Widget> footer;

  final int itemCount;

  /// Builds one row. Called only for the rows near the viewport.
  final IndexedWidgetBuilder itemBuilder;

  /// Divider between rows ([LazyListStyle.plain] only).
  final IndexedWidgetBuilder? separatorBuilder;

  final EdgeInsets padding;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final LazyListStyle style;

  /// Rendered in place of the rows when [itemCount] is 0 — the empty state the
  /// feature owns, instead of a scroll view with nothing in it.
  final Widget? emptyPlaceholder;

  @override
  Widget build(BuildContext context) {
    final Widget? rows = itemCount == 0
        ? (emptyPlaceholder == null
            ? null
            // Fill the remaining viewport: the empty state stays centred like a
            // full body, while the header above it (search box, chips) stays
            // reachable instead of scrolling away.
            : SliverFillRemaining(
                hasScrollBody: false,
                child: emptyPlaceholder,
              ))
        : switch (style) {
            LazyListStyle.plain => LazyListSliver(
                itemCount: itemCount,
                itemBuilder: itemBuilder,
                separatorBuilder: separatorBuilder,
              ),
            LazyListStyle.card => LazyCardSliver(
                itemCount: itemCount,
                itemBuilder: itemBuilder,
              ),
          };

    return CustomScrollView(
      controller: controller,
      physics: physics,
      slivers: [
        SliverPadding(
          padding: padding,
          sliver: SliverMainAxisGroup(
            slivers: [
              if (header.isNotEmpty)
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: header,
                  ),
                ),
              ?rows,
              if (footer.isNotEmpty)
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: footer,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The rows themselves, as a sliver: only the rows near the viewport exist.
class LazyListSliver extends StatelessWidget {
  const LazyListSliver({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.separatorBuilder,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// Divider between rows; omit for none.
  final IndexedWidgetBuilder? separatorBuilder;

  @override
  Widget build(BuildContext context) {
    final separator = separatorBuilder;
    if (separator == null) {
      return SliverList.builder(
        itemCount: itemCount,
        itemBuilder: itemBuilder,
      );
    }
    return SliverList.separated(
      itemCount: itemCount,
      itemBuilder: itemBuilder,
      separatorBuilder: separator,
    );
  }
}

/// Rows inside ONE outlined card, built lazily.
///
/// Flutter cannot put a `Card` around a sliver, and what a `Card` draws is only
/// a background + border + rounded ends — so the chrome is painted per row from
/// the *theme's* `CardTheme` instead of wrapping the whole list. The result is
/// the same single card (first row keeps the top corners, last row the bottom
/// ones, the sides run continuously) with the rows still lazily built, and a
/// theme change keeps propagating because nothing here hard-codes a colour or a
/// radius.
class LazyCardSliver extends StatelessWidget {
  const LazyCardSliver({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;

  /// Builds the row CONTENT (no card chrome, no page padding).
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return SliverList.builder(
      itemCount: itemCount,
      itemBuilder: (context, index) => _CardRow(
        isFirst: index == 0,
        isLast: index == itemCount - 1,
        child: itemBuilder(context, index),
      ),
    );
  }
}

/// One row of a [LazyCardSliver]: the shared card's background, side borders
/// and — for the ends — its rounded corners.
class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.isFirst,
    required this.isLast,
    required this.child,
  });

  final bool isFirst;
  final bool isLast;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardTheme = theme.cardTheme;
    final shape = cardTheme.shape;
    final BorderRadius radius =
        shape is RoundedRectangleBorder && shape.borderRadius is BorderRadius
            ? shape.borderRadius as BorderRadius
            : BorderRadius.circular(12);
    final BorderSide side =
        shape is RoundedRectangleBorder ? shape.side : BorderSide.none;
    // Same resolution the Card widget itself uses, so an unset colour still
    // matches Material 3's card surface.
    final Color color =
        cardTheme.color ?? theme.colorScheme.surfaceContainerLow;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        border: Border(
          left: side,
          right: side,
          top: isFirst ? side : BorderSide.none,
          bottom: isLast ? side : BorderSide.none,
        ),
        borderRadius: BorderRadius.only(
          topLeft: isFirst ? radius.topLeft : Radius.zero,
          topRight: isFirst ? radius.topRight : Radius.zero,
          bottomLeft: isLast ? radius.bottomLeft : Radius.zero,
          bottomRight: isLast ? radius.bottomRight : Radius.zero,
        ),
      ),
      // A row's ListTile paints its background/ink on the nearest Material;
      // a transparent one here stands in for the Card the rows used to live
      // in, so ripples render above the card surface instead of failing
      // ListTile's debug assertion.
      child: Material(
        type: MaterialType.transparency,
        child: child,
      ),
    );
  }
}