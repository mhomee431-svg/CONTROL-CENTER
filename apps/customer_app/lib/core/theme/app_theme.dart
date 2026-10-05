import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The approved HyperLocal palette.
///
/// Tokens live here rather than inline at call sites so the direction can be
/// re-tuned in one place. Every colour below is from the approved direction:
/// Royal Blue + Electric Blue as the primary pair, White / Very Light Gray as
/// the surface pair, Green for success, Orange for highlight, Red for error,
/// and Dark Slate for body text.
class AppColors {
  // ── Primary: Royal Blue, with Electric Blue as its brighter companion ─────
  /// The deep royal blue. Primary actions, app bars, links.
  static const primary = Color(0xFF2563EB);

  /// Electric blue — the same hue, lifted. Used for emphasis and for the
  /// gradient's leading edge so primary surfaces feel lit rather than flat.
  static const primaryLight = Color(0xFF3B82F6);

  /// A softer blue for tinted fills (selected chips, info banners) that must
  /// not compete with a real primary action.
  static const primarySurface = Color(0xFFDBEAFE);

  /// Green for success: open now, in stock, delivered, confirmed.
  static const success = Color(0xFF10B981);

  /// Green tint for success backgrounds.
  static const successSurface = Color(0xFFD1FAE5);

  /// The approved palette names this "Green success"; the M3 [ColorScheme] slot
  /// it fills is `secondary`, so the scheme keeps that name. Retained because
  /// `success` alone would have broken 47 call sites for a rename that buys
  /// nothing — the two describe the same approved green.
  static const secondary = Color(0xFF10B981);

  // ── Orange highlight: "act on this soon" ──────────────────────────────────
  /// Orange highlight — low stock, closing soon, expiring, pending.
  ///
  /// Orange is deliberately NOT a status colour like green or red. It means
  /// "this needs your attention", which is why it had no token and was written
  /// inline as `Colors.orange` in eleven places. Those call sites were picking
  /// Flutter's amber 500 and then `.shade800` for text — a different, darker
  /// orange — so one logical state rendered in two unrelated hues depending on
  /// which widget showed it. `warning` and `warningSurface` make the pair a
  /// decision rather than an accident.
  static const warning = Color(0xFFF59E0B);

  /// Orange tint for highlight backgrounds.
  static const warningSurface = Color(0xFFFEF3C7);

  /// Red for errors: failed, offline, destructive confirmations.
  static const error = Color(0xFFEF4444);

  /// Red tint for error backgrounds.
  static const errorSurface = Color(0xFFFEE2E2);

  // ── Surfaces ─────────────────────────────────────────────────────────────
  /// White — the primary surface in light mode.
  static const surfaceLight = Colors.white;

  /// Very light gray — the app background, one step below the surface so cards
  /// read as raised without needing a heavy shadow.
  static const backgroundLight = Color(0xFFF8FAFC);

  /// Dark slate surface for dark mode.
  static const surfaceDark = Color(0xFF1E293B);

  /// Darker slate page background for dark mode.
  static const backgroundDark = Color(0xFF0F172A);

  // ── Text ─────────────────────────────────────────────────────────────────
  /// Dark slate body text. High contrast against white.
  static const textLight = Color(0xFF0F172A);

  /// Near-white text for dark mode.
  static const textDark = Color(0xFFF8FAFC);

  /// Muted slate for secondary metadata (timestamps, captions, helper text).
  ///
  /// 4.76:1 on white and 4.55:1 on [backgroundLight] — just over the 4.5:1
  /// WCAG AA threshold for normal text, which is what this is: small secondary
  /// copy. It is the *tightest* token in the light palette, so any change to it
  /// should be re-measured rather than eyeballed.
  static const textMuted = Color(0xFF64748B);

  /// Muted slate for DARK surfaces.
  ///
  /// [textMuted] scores only 3.07:1 on [surfaceDark] — it fails AA in dark mode,
  /// because a mid-tone grey that reads as "quiet but present" on white
  /// disappears against a dark background. Dark mode therefore needs its own
  /// muted token rather than reusing the light one.
  static const textMutedDark = Color(0xFF94A3B8); // 5.71:1 on surfaceDark

  // ── Accessible status TEXT ────────────────────────────────────────────────
  //
  // WHY THESE EXIST, WITH NUMBERS
  // ------------------------------
  // [success], [warning] and [error] are *vivid* so they read as fills, borders
  // and icons. Measured as TEXT on a light surface they fail WCAG AA badly:
  //
  //   success #10B981 on white ....... 2.54:1   (needs 4.5)
  //   warning #F59E0B on white ....... 2.15:1
  //   error   #EF4444 on white ....... 3.76:1
  //
  // So "Low Stock" and "In Stock" were, quite literally, the least readable
  // text on the card — a status the customer most needs to read. The very same
  // hues score 5.3-8.8:1 on DARK surfaces, which is why one colour could never
  // serve both: it is not that the hue is wrong, it is that a saturated mid-tone
  // needs a different lightness per background.
  //
  // Rule: vivid tokens for FILLS, BORDERS and ICONS; the `*Text` tokens below
  // for anything a customer has to READ.
  static const successText = Color(0xFF047857); // 5.48:1 white, 5.24:1 bg
  static const warningText = Color(0xFFB45309); // 5.02:1 white, 4.80:1 bg
  static const errorText = Color(0xFFDC2626); // 4.83:1 white, 4.62:1 bg

  /// Primary as READABLE text, for links and inline emphasis.
  ///
  /// [primary] (5.17:1) passes on white but [primaryLight] — used for gradient
  /// highlights — is only 3.68:1, so it must never carry text.
  static const primaryText = Color(0xFF1D4ED8); // 6.70:1 white, 6.41:1 bg

  // ── Accessible status text on DARK surfaces ───────────────────────────────
  // Lightened variants; the vivid light-mode hues already pass on dark, but
  // these keep a single pair to reason about in ThemeData.
  static const successTextDark = Color(0xFF34D399); // 7.61:1 on surfaceDark
  static const warningTextDark = Color(0xFFFBBF24); // 8.76:1 on surfaceDark
  static const errorTextDark = Color(0xFFF87171); // 5.29:1 on surfaceDark
  static const primaryTextDark = Color(0xFF93C5FD);

  /// Hairline and outline colour.
  static const border = Color(0xFFE2E8F0);

  // ── Soft shadows ─────────────────────────────────────────────────────────
  /// The shadow colour behind every elevation in the app.
  ///
  /// A blue-black rather than pure black: a neutral black shadow over a cool
  /// white/gray surface reads as grey dirt, while a shadow tinted toward the
  /// brand's own hue reads as the surface sitting in the same light as
  /// everything else. Pure `Colors.black` at any opacity looks dirty against
  /// #F8FAFC; this does not.
  static const shadow = Color(0xFF0F172A);
}

/// The app's one card decoration: rounded corners + a soft shadow.
///
/// WHY A HELPER RATHER THAN A SHADOW WRITTEN AT EACH CALL SITE
/// ---------------------------------------------------------
/// `shop_card` and `product_card` had byte-identical hand-written shadows
/// (`Colors.black @ 5%`, blur 4, offset 0,2) and there were ~34 `BoxShadow`
/// literals across the app, each tuned by whoever was nearest. That is how a
/// design language drifts: nothing is wrong on any one screen, and nothing
/// matches.
///
/// Routing every card through one function means the "rounded cards + soft
/// shadows" half of the approved direction is applied by construction — a new
/// card cannot accidentally invent a fifth shadow style, because it calls this.
///
/// [AppShadows.soft] supplies two layers (tight contact + wide ambient). One
/// wide blur reads as a blur; the pair reads as a surface lifted off the page.
/// The colour comes from [AppColors.shadow], a blue-black rather than pure
/// black, so the shadow belongs to the same light as the surfaces it falls on.
BoxDecoration appCardDecoration({
  required Color color,
  double radius = AppRadius.md,
  List<BoxShadow>? shadow,
}) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: shadow ?? AppShadows.soft,
  );
}

/// The app's type scale.
///
/// WHY THIS EXISTS
/// ---------------
/// Typography was the last uncentralised corner of the design system: 279
/// `fontSize:` literals spread across screens, spanning FIFTEEN distinct values
/// — 11, 12, 13, 14, 15 all appear, each one a single point apart. Nobody
/// invented that. It accreted one screen at a time, and the result is that
/// "clear hierarchy" had quietly stopped existing: 11/12/13/14 are
/// indistinguishable at arm's length, so nothing reads as more important than
/// anything else.
///
/// The scale below collapses that to eight steps chosen for legibility on a
/// phone, with real gaps between the small end. A screen picks a ROLE
/// ("this is a caption", "this is a section title") rather than a number, so
/// two screens cannot disagree about what a caption looks like.
///
/// Sizes are the role; [AppTypography.textTheme] wires them into Flutter's
/// `TextTheme` so Material widgets inherit them too.
class AppTypography {
  // ── The scale ─────────────────────────────────────────────────────────────
  /// Dense metadata: a stock timestamp, a "3 items" count.
  ///
  /// 12 is the floor. 11 and below stops being legible on a cheap phone at arm's
  /// length, and the app is used one-handed, outdoors, while walking.
  static const double caption = 12.0;

  /// The default body size. Also a caption's large sibling for secondary copy.
  static const double body = 14.0;

  /// Default body for long-form reading (policy text, descriptions).
  static const double bodyLarge = 16.0;

  /// Card and list-row titles — the most common "make this read as a title"
  /// size in the app.
  static const double title = 18.0;

  /// Screen-level titles and app-bar headings.
  static const double titleLarge = 20.0;

  /// Page hero. Rare, and should stay rare: a screen with two of these has none.
  static const double display = 24.0;

  /// Button labels. Fixed rather than derived so a button's type never shifts
  /// when the surrounding scale is retuned.
  static const double button = 15.0;

  // ── Weights ───────────────────────────────────────────────────────────────
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semiBold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;

  // ── Line heights ──────────────────────────────────────────────────────────
  /// Body copy breathes; captions do not. A shared line height across both is
  /// what makes dense metadata look like an accident.
  static const double bodyLineHeight = 1.45;
  static const double tightLineHeight = 1.25;

  // ── Material integration ──────────────────────────────────────────────────
  /// Maps the scale onto Flutter's `TextTheme`.
  ///
  /// Applied through the theme so M3 components (list tiles, dialogs, app bar)
  /// inherit the same scale as hand-styled text instead of drifting to the
  /// platform default.
  static TextTheme textTheme(TextTheme base) {
    return base.copyWith(
      displaySmall: base.displaySmall?.copyWith(
        fontSize: display,
        fontWeight: bold,
        height: tightLineHeight,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: titleLarge,
        fontWeight: semiBold,
        height: tightLineHeight,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: titleLarge,
        fontWeight: semiBold,
        height: tightLineHeight,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: title,
        fontWeight: semiBold,
        height: tightLineHeight,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: bodyLarge,
        fontWeight: medium,
        height: tightLineHeight,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: bodyLarge,
        height: bodyLineHeight,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: body,
        height: bodyLineHeight,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: caption,
        height: bodyLineHeight,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: button,
        fontWeight: medium,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: body,
        fontWeight: medium,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: caption,
        fontWeight: medium,
      ),
    );
  }
}

/// Central button styles.
///
/// WHY THESE EXIST ALONGSIDE THE THEME'S `*ButtonThemeData`
/// ---------------------------------------------------
/// The theme already styles every button by DEFAULT, which covers most screens.
/// These cover the cases a theme cannot express: a button that must be full
/// width (a form's submit), one that must sit inside a fixed row, and one whose
/// height is the accessibility floor rather than the default. Hand-writing
/// `ButtonStyle(...)` at a call site is how two "submit" buttons end up 44 and
/// 52 tall on adjacent screens.
class AppButtons {
  /// The full-width submit used by every form in the app.
  static const Size fullWidth = Size(double.infinity, 48);

  /// A square button sized to the touch floor — the FAB and icon-only actions.
  static const Size square = Size(
    AppTouchTarget.minSize,
    AppTouchTarget.minSize,
  );

  /// A button that must not resize when its label changes length ("Add" →
  /// "Add to cart"), so a spinner swap cannot shift the layout under the thumb.
  static const Size fixed = Size(120, 48);
}

/// Central input styles.
///
/// Inputs are where per-screen drift is most visible: the same search field
/// appeared with three different corner radii and two different fill colours
/// depending on which screen asked for it. These name the two shapes the app
/// actually uses so a new field copies one instead of inventing a third.
class AppInputs {
  /// The standard field — search bars, forms, text entry.
  static BorderRadius get standard => BorderRadius.circular(AppRadius.md);

  /// A field inside a card or sheet, where the extra border would read as a
  /// border-inside-a-border.
  static BorderRadius get flush => BorderRadius.circular(AppRadius.sm);
}

/// Spacing scale.
///
/// A 4pt base with comfortable, mobile-first steps. `xs` is for icon-to-label
/// gaps inside a control; `md` is the default gutter between unrelated blocks;
/// `xxl` exists so a screen's main sections are separated by something visibly
/// larger than the padding inside them, which is what makes hierarchy readable
/// without adding borders.
class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;

  /// The standard page gutter. Screens pad by this rather than by `md`, so the
  /// edge margin is consistent everywhere instead of drifting per screen.
  static const double pageGutter = md;

  /// Space between a control and the label directly beneath it.
  static const double controlToLabel = sm;
}

/// Corner radii — the "rounded" half of the design language.
///
/// One scale rather than a radius typed at each call site, so cards, inputs,
/// sheets and chips round at the same ratios and the app reads as a single
/// system.
class AppRadius {
  /// Chips, badges, small thumbnails.
  static const double sm = 8.0;

  /// The default. Cards, list tiles, text fields.
  static const double md = 12.0;

  /// Panels and large media blocks.
  static const double lg = 16.0;

  /// Dialogs and bottom sheets, where M3 asks for a generous corner.
  static const double xl = 28.0;
}

/// Soft shadows.
///
/// WHY NOT `elevation`
/// ------------------
/// Flutter's `elevation` derives a shadow's colour and offset from the theme's
/// brightness, so an elevated card picks up a different shadow in dark mode than
/// in light and a heavy one in neither. The approved direction calls for SOFT
/// shadows — a wide, low-opacity lift — which is expressed directly here so it
/// is identical in both modes and tuned once.
///
/// [AppColors.shadow] supplies a blue-black rather than pure black so the
/// shadow belongs to the same light as the surfaces it falls on.
class AppShadows {
  /// Cards resting on the page background.
  ///
  /// Two layers, not one: a tight contact shadow plus a wide ambient one. One
  /// box-shadow at a large blur looks like a blur; the pair is what reads as a
  /// surface lifted a millimetre off the page.
  static const List<BoxShadow> soft = [
    BoxShadow(color: Color(0x0D0F172A), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0F0F172A), blurRadius: 12, offset: Offset(0, 4)),
  ];

  /// Raised above other cards — a menu, a floating action control.
  static const List<BoxShadow> raised = [
    BoxShadow(color: Color(0x140F172A), blurRadius: 4, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x1A0F172A), blurRadius: 24, offset: Offset(0, 12)),
  ];
}

/// Minimum interactive size, in logical pixels.
///
/// 48dp is the accessibility floor (Material and WCAG both land here), and it
/// is treated as a floor rather than a suggestion: a control that reports
/// itself as smaller is a control a customer with a large thumb or a shaky hand
/// will miss.
class AppTouchTarget {
  /// The floor for any tappable control.
  static const double minSize = 48.0;

  /// Wraps [child] so it presents at least [minSize] in both axes while still
  /// rendering its own (possibly smaller) content — so a 20dp icon can be padded
  /// up to a 48dp target without the icon itself being drawn larger.
  static Widget atLeast(Widget child) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: minSize, minHeight: minSize),
      child: child,
    );
  }
}

/// Builds the component themes that both brightnesses share.
///
/// WHY ONE BUILDER
/// ---------------
/// M3's dark theme is the SAME scheme with inverted roles, not a second set of
/// ad-hoc values. Writing the component themes twice is how a role ends up
/// present in light mode and missing in dark — a screen then renders a
/// light-only colour on a dark surface. One builder makes a divergence
/// impossible to write.
ThemeData _buildComponents({
  required ColorScheme scheme,
  required TextTheme textTheme,
  required Color scaffoldBackground,
}) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scaffoldBackground,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      // M3's scroll-under tint. `elevation: 0` alone leaves the bar flat when
      // content scrolls beneath it, which reads as Material 2.
      scrolledUnderElevation: 3,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: AppTypography.title,
        fontWeight: AppTypography.semiBold,
        height: AppTypography.tightLineHeight,
      ),
    ),
    // M3 puts dialogs on a raised container with a 28dp radius. Without this
    // they keep the M2 white sheet + shadow look, so dialogs became the one
    // surface that still looked like the previous design system.
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      // M3 tints elevated surfaces with `surfaceTintColor`. Left at its default
      // it paints a brand-coloured haze over every card.
      surfaceTintColor: Colors.transparent,
      // The approved direction asks for SOFT shadows, so elevation is set to 0
      // and the depth is carried by [AppShadows.soft] instead. A Flutter
      // `elevation` shadow is neither soft nor consistent across both
      // brightnesses — it is derived from the theme, so the same card lifts
      // differently in light and dark.
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    ),
    // M3 filled buttons are pill-shaped and 48dp tall. The square M2
    // `ElevatedButton` outline is the most recognisable leftover when M2 and M3
    // are mixed, and every "Try again"/"Submit" control shows it at once.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: const Size(64, 48),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: const Size(64, 48),
        side: BorderSide(color: scheme.outline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: const Size(48, 48),
      ),
    ),
    // M3 switches are wide with an icon in the thumb.
    switchTheme: SwitchThemeData(
      thumbIcon: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const Icon(Icons.check, size: 16);
        }
        return null;
      }),
    ),
    // "Large touch targets": icon buttons carry only a glyph, so without an
    // explicit floor they size to the 24dp icon and sit far below the 48dp
    // accessibility minimum. Flutter's own default is 48, which is correct —
    // stated here so the guarantee is visible in the theme rather than
    // inherited, and so a future tightening of this theme cannot quietly drop
    // it below the floor.
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(AppTouchTarget.minSize, AppTouchTarget.minSize),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      space: 1,
      thickness: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      side: BorderSide(color: scheme.outlineVariant),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainer,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: scheme.outline),
      ),
      // M3 signals focus with a 2dp primary-coloured border, not a glow.
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
  );
}

class AppTheme {
  /// The Material 3 light scheme.
  ///
  /// WHY EVERY ROLE IS FILLED
  /// -----------------------
  /// This theme declared `useMaterial3: true` but supplied only `primary`,
  /// `secondary`, `surface`, `error` and `onSurface`. Material 3 components read
  /// ~20 roles (`onPrimary`, `primaryContainer`, `outlineVariant`, the
  /// `surfaceContainer*` tint ladder, `inverseSurface`, …). An unspecified role
  /// silently falls back to Flutter's stock purple/grey, so M3 widgets —
  /// FilledButton, Card, Dialog, Chip — rendered in colours belonging to no part
  /// of this brand. The flag was never the point; the roles are.
  ///
  /// Every role is DERIVED from the existing brand palette, so the app keeps the
  /// colours it shipped with and only gains the missing members.
  static ThemeData get lightTheme {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.primarySurface,
      onPrimaryContainer: Color(0xFF1E3A8A),
      // Electric blue is the lighter companion in the approved primary pair. M3
      // has no second primary slot, and `secondary` is already spoken for by
      // GREEN success, so electric blue takes the `tertiary` role — the one slot
      // free to carry "a second brand colour" without stealing a semantic.
      secondary: AppColors.success,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.successSurface,
      onSecondaryContainer: Color(0xFF065F46),
      tertiary: AppColors.primaryLight,
      onTertiary: Color(0xFF0B1220),
      error: AppColors.error,
      onError: Colors.white,
      errorContainer: AppColors.errorSurface,
      onErrorContainer: Color(0xFF7F1D1D),
      surface: AppColors.surfaceLight,
      onSurface: AppColors.textLight,
      // The M3 surface tint ladder the components actually read for cards,
      // sheets and menus. `surface`/`onSurface` above are unchanged.
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Color(0xFFFBFDFF),
      surfaceContainer: Color(0xFFF1F5F9),
      surfaceContainerHigh: Color(0xFFEAEFF5),
      surfaceContainerHighest: Color(0xFFE2E8F0),
      onSurfaceVariant: AppColors.textMuted,
      outline: Color(0xFFCBD5E1),
      outlineVariant: Color(0xFFE2E8F0),
      inverseSurface: Color(0xFF1E293B),
      onInverseSurface: Color(0xFFF8FAFC),
      inversePrimary: Color(0xFF93C5FD),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
    );

    return _buildComponents(
      scheme: scheme,
      scaffoldBackground: AppColors.backgroundLight,
      // The scale is applied HERE, once per brightness, rather than at each call
      // site. Material widgets (ListTile, Dialog, AppBar) read `textTheme`, so
      // this single mapping is what stops them drifting back to the platform
      // default while hand-styled text uses the scale.
      textTheme: AppTypography.textTheme(
        GoogleFonts.interTextTheme(ThemeData.light().textTheme).apply(
          bodyColor: AppColors.textLight,
          displayColor: AppColors.textLight,
        ),
      ),
    );
  }

  /// The Material 3 dark scheme — the light scheme with inverted roles.
  ///
  /// M3 models dark mode as one scheme per brightness, not a separate palette.
  /// A role present in light and absent here is exactly how a screen ends up
  /// rendering a light-only colour on a dark surface, so both schemes declare
  /// the same complete role set.
  static ThemeData get darkTheme {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      // A saturated brand blue fails contrast as text on a dark surface, so dark
      // uses the light tint of the same hue — same brand, readable on dark.
      primary: Color(0xFF93C5FD),
      onPrimary: Color(0xFF1E3A8A),
      primaryContainer: Color(0xFF1E3A8A),
      onPrimaryContainer: AppColors.primarySurface,
      secondary: Color(0xFF6EE7B7),
      onSecondary: Color(0xFF065F46),
      secondaryContainer: Color(0xFF065F46),
      onSecondaryContainer: AppColors.successSurface,
      // Same mapping as light: electric blue holds `tertiary` in both.
      tertiary: AppColors.primary,
      onTertiary: Colors.white,
      error: Color(0xFFFCA5A5),
      onError: Color(0xFF7F1D1D),
      errorContainer: Color(0xFF7F1D1D),
      onErrorContainer: AppColors.errorSurface,
      surface: AppColors.surfaceDark,
      onSurface: AppColors.textDark,
      surfaceContainerLowest: Color(0xFF0B1220),
      surfaceContainerLow: Color(0xFF172033),
      surfaceContainer: Color(0xFF1E293B),
      surfaceContainerHigh: Color(0xFF263449),
      surfaceContainerHighest: Color(0xFF334155),
      onSurfaceVariant: Color(0xFF94A3B8),
      outline: Color(0xFF475569),
      outlineVariant: Color(0xFF334155),
      inverseSurface: Color(0xFFE2E8F0),
      onInverseSurface: Color(0xFF1E293B),
      inversePrimary: AppColors.primary,
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
    );

    return _buildComponents(
      scheme: scheme,
      scaffoldBackground: AppColors.backgroundDark,
      textTheme: AppTypography.textTheme(
        GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(
          bodyColor: AppColors.textDark,
          displayColor: AppColors.textDark,
        ),
      ),
    );
  }
}
