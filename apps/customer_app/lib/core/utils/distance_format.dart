/// The ONE place a distance becomes text.
///
/// ## The rule
/// Metres below 1 km, kilometres at or above it, one decimal, trailing zeros
/// dropped:
///
///   850 m   -> "850 m"     (rounded to the nearest 10 m)
///   1.2 km  -> "1.2 km"
///   4.8 km  -> "4.8 km"
///   5.0 km  -> "5 km"      not "5.0 km" — "5 km" is how people write it
///
/// ## Why this file exists
/// Seven places formatted a distance independently and all seven disagreed:
///
///  * `shop_card`, `shop_product_card`, `search_results_by_pin_screen`,
///    `search_results_map_view`, `map_route`, `share_content`,
///    `search_filter_sort_bar` all did `toStringAsFixed(1)` — so a shop 850 m
///    away rendered as **"0.8 km"**, losing both the useful precision and any
///    resemblance to how far away it actually is.
///  * `shop_header` did NO rounding at all: `'${shop.distanceInKm} km away'`.
///    That prints `0.85 km away`, `1.2 km away`, and — for a value that has been
///    through arithmetic — `0.30000000000000004 km away`.
///
/// ## Units
/// Every entry point is explicit about its unit and there is no default, because
/// this app has genuinely mixed units in flight: the backend sends `distance_km`,
/// while `MapAdapter.haversineMeters` returns **metres**. A single default unit
/// is how the two get confused.
library;

/// Formats a distance given in METRES.
String formatMeters(
  num? meters, {
  DistanceStyle style = DistanceStyle.compact,
}) {
  if (meters == null) return DistanceFormat.unknownText;

  final m = meters.toDouble();
  if (m.isNaN || m.isNegative) return DistanceFormat.unknownText;

  if (m < 1000) return _metres(m, style);

  return _kilometres(m / 1000, style);
}

/// Formats a distance given in KILOMETRES (what the API sends).
String formatKilometers(
  num? kilometers, {
  DistanceStyle style = DistanceStyle.compact,
}) {
  if (kilometers == null) return DistanceFormat.unknownText;

  final km = kilometers.toDouble();
  if (km.isNaN || km.isNegative) return DistanceFormat.unknownText;

  // The backend uses 0 as "distance not known". Printing "0 km" would be a
  // confident lie, so this is the one case that collapses to unknown.
  if (km == 0) return DistanceFormat.unknownText;

  return km < 1 ? _metres(km * 1000, style) : _kilometres(km, style);
}

/// Below 1 km we count in metres. Rounded to the nearest 10 m because a GPS
/// fix is not accurate to 1 m and "847 m" implies a precision that is a fiction.
String _metres(double m, DistanceStyle style) {
  final rounded = (m / 10).round() * 10;
  // Rounding can land on 1000 (999 m -> 1000 m), which must read as "1 km".
  if (rounded >= 1000) return _kilometres(rounded / 1000, style);
  return '$rounded m';
}

String _kilometres(double km, DistanceStyle style) {
  // 1 decimal below 10 km ("4.8 km"); whole kilometres above it, because
  // "23.4 km" implies a precision nobody needs for a neighbourhood app.
  final text = km < 10
      ? _trimTrailingZero(km.toStringAsFixed(1))
      : '${km.round()}';
  return style == DistanceStyle.withUnitSuffix ? '$text km away' : '$text km';
}

/// "5.0" -> "5", but leaves "4.8" alone. Avoids "5.0 km" and keeps "1.2 km".
String _trimTrailingZero(String fixed) =>
    fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;

/// How the text reads in context.
enum DistanceStyle {
  /// "850 m" / "1.2 km" — the default, for chips, cards and map labels.
  compact,

  /// "1.2 km away" — for a sentence-like spot such as a shop header.
  withUnitSuffix,
}

/// Shared wording, so "unknown" is never spelled three ways.
abstract final class DistanceFormat {
  /// Shown when there is no real measurement.
  ///
  /// The backend sends `0` for an unresolvable distance. Rendering "0 km" would
  /// tell the customer the shop is in their pocket; omitting it is the honest
  /// answer and is what the existing cards already do.
  static const String unknownText = '';
}
