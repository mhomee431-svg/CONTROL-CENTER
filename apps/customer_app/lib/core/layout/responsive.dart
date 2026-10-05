import 'package:flutter/material.dart';

/// Layout decisions that depend on the SIZE OF THE SPACE AVAILABLE.
///
/// WHY THIS EXISTS
/// ---------------
/// Only eight call sites in the whole app consulted `MediaQuery`, and none did so
/// through a shared vocabulary -- each re-derived "is this a big screen?" inline.
/// So the same phone can be classified two different ways by two screens, and a
/// layout tuned for one device silently overflows on another.
///
/// The failure is not hypothetical. A horizontal carousel hard-coded to
/// `height: 200` overflows the moment a customer raises their system font size --
/// exactly what someone with a low-vision prescription does. A layout that
/// ignores available space is not "not responsive" in the abstract; it is broken
/// for a real group of users.
///
/// The principle throughout: **derive layout from the constraints the parent
/// actually gave you** ([LayoutBuilder]), never from device model, screen inches,
/// or a hard-coded coordinate. `MediaQuery` reads the WINDOW, which is a
/// different and less reliable thing than the box a widget was handed -- the two
/// disagree inside dialogs, sheets and split views.
class Responsive {
  const Responsive._();

  // ── Width classes ─────────────────────────────────────────────────────────
  /// Below this the layout is a single column. 600dp is the Material "medium"
  /// boundary, chosen because it is where a phone-class layout genuinely stops
  /// fitting content rather than an arbitrary round number.
  static const double mediumWidth = 600.0;

  /// At or above this, multi-column and side-by-side layouts become viable.
  ///
  /// 768 rather than Material's 840, because the reference tablet's PORTRAIT
  /// width is 834 (iPad) — 834 is smaller than 840, so Material's own number
  /// classifies an iPad in portrait as "medium" and denies it the tablet layout
  /// it plainly has the room for. 768 is the long-standing tablet-portrait
  /// boundary (the original iPad was exactly 768 wide) and puts real tablets on
  /// the right side of the line. Tested against 834 explicitly.
  static const double expandedWidth = 768.0;

  /// Beyond this the content stops stretching and is centred instead. A form
  /// stretched across 1200dp is harder to read than the same form in a 600dp
  /// column: the eye has to travel further between a label and its field.
  ///
  /// 1024 is the classic tablet-LANDSCAPE width, so a rotated tablet gets the
  /// centred layout and a phone in landscape (844dp wide) does not — 844dp is
  /// still a single screenful, not a reading distance.
  static const double largeWidth = 1024.0;

  /// The widest a single readable column is ever allowed to become.
  static const double maxReadableWidth = 640.0;

  // ── Height classes ────────────────────────────────────────────────────────
  /// Height under this is a short device or landscape-on-a-phone. Vertical space
  /// is the scarce resource, so side-by-side beats stacked.
  ///
  /// 500 rather than 600: the smallest real PORTRAIT phone is 568 tall (the
  /// original iPhone SE class), and classing that as "short" would mean every
  /// small phone is told it is landscape. The boundary sits below the shortest
  /// real portrait device and above a phone lying on its side (~390), which is
  /// the state this is actually meant to detect.
  static const double shortHeight = 500.0;

  /// Width class for a given available width.
  static WidthClass widthClassFor(double width) {
    if (width >= largeWidth) return WidthClass.large;
    if (width >= expandedWidth) return WidthClass.expanded;
    if (width >= mediumWidth) return WidthClass.medium;
    return WidthClass.compact;
  }

  /// Height class for a given available height.
  static HeightClass heightClassFor(double height) =>
      height < shortHeight ? HeightClass.short : HeightClass.tall;

  /// Centres [child] and caps its width on wide screens.
  ///
  /// The single highest-value helper here. A column of form fields or a list is
  /// perfectly usable at 380dp and genuinely unpleasant at 1200dp, and the fix
  /// is one wrapper rather than per-screen arithmetic. On a phone it is a no-op,
  /// so it is always safe to apply.
  static Widget readableWidth({
    required Widget child,
    double maxWidth = maxReadableWidth,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }

  /// A horizontal gutter appropriate to the width.
  ///
  /// A phone wants its content near the edges; a tablet wants it pulled in, or
  /// text lines run long enough to be hard to track back. Scaling by width keeps
  /// the ratio comfortable from a 320dp phone to a 1200dp tablet with no
  /// per-device numbers.
  static double gutterFor(double width) {
    if (width >= largeWidth) return 32.0;
    if (width >= expandedWidth) return 24.0;
    if (width >= mediumWidth) return 20.0;
    return 16.0;
  }

  /// Columns a grid should use at [width] for cards of [itemWidth] plus [gap].
  ///
  /// Bounded below by 1 so a very narrow screen degrades to a single column
  /// rather than dividing by something too small and producing zero or a
  /// negative count.
  static int columnsFor({
    required double width,
    required double itemWidth,
    double gap = 12.0,
  }) {
    if (itemWidth <= 0) return 1;
    final fit = ((width + gap) / (itemWidth + gap)).floor();
    return fit < 1 ? 1 : fit;
  }

  /// A height for a horizontally-scrolling carousel, derived from the content's
  /// own needs rather than hard-coded.
  ///
  /// Use this INSTEAD of `SizedBox(height: 200)`. A fixed carousel height is the
  /// most common responsive bug in a card list: tuned on the designer's phone, it
  /// overflows for a customer with larger system text because the card grows and
  /// the box does not.
  ///
  /// Capped, because at 4x text a 900dp-tall carousel is useless -- past the cap
  /// the content scrolls inside the box instead.
  ///
  /// The cap is a MULTIPLE of the base height, not an absolute number, and that
  /// detail is load-bearing. An absolute cap (`maxHeight = 420`) looks harmless
  /// and is quietly wrong: a 240px rail reaches it at 1.75x and then stops
  /// growing, so from 1.75x all the way to the app-wide 2.5x clamp the rail sits
  /// frozen at a fixed 420 while its card keeps getting taller. That is exactly
  /// the clipping this function exists to prevent, reintroduced through the cap.
  ///
  /// Tying the cap to the base keeps it proportional, so the rail tracks the
  /// text across the entire supported range and only ever stops at the clamp.
  static double carouselHeight({
    required double baseHeight,
    required TextScaler textScale,
    double maxScale = 2.5,
  }) {
    final scaled = baseHeight * textScale.scale(1.0);
    final cap = baseHeight * maxScale;
    return scaled > cap ? cap : scaled;
  }
}

/// Width classes, smallest first.
enum WidthClass {
  /// Phone portrait. One column, everything stacked.
  compact,

  /// Large phone / small tablet portrait. Still one column, more breathing room.
  medium,

  /// Tablet. Multi-column becomes viable.
  expanded,

  /// Large tablet / desktop window. Content centred and width-capped.
  large;

  bool get isCompact => this == WidthClass.compact;

  /// True from [expanded] up: the point where side-by-side beats stacked.
  bool get isWide => this == WidthClass.expanded || this == WidthClass.large;
}

/// Height classes.
enum HeightClass {
  /// A small phone, or a phone in landscape.
  short,
  tall;

  bool get isShort => this == HeightClass.short;
}
