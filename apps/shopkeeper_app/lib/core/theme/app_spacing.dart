/// Centralized spacing tokens — the SINGLE source of truth for all margins,
/// padding, and gaps in the app.
///
/// Token values follow a 4px grid:
///   xs = 4, sm = 8, md = 16, lg = 24, xl = 32, xxl = 48, xxxl = 64
library;
abstract final class AppSpacing {
  AppSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
  static const double xxxl = 64.0;

  /// Compact form padding (e.g. tight fields on mobile).
  static const double formField = 12.0;

  /// Standard list-item vertical padding.
  static const double listItemVertical = 14.0;

  /// Standard list-item horizontal padding.
  static const double listItemHorizontal = 16.0;
}
