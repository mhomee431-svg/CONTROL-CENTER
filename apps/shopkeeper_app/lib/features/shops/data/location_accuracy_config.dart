import 'package:geolocator/geolocator.dart';

/// Quality tier of a single GPS reading (never "100% accurate").
enum AccuracyTier { excellent, good, acceptable, weak, poor, unknown }

/// Centralized, single-source-of-truth location accuracy configuration.
///
/// Every accuracy threshold, timeout and staleness window used by the shop
/// location capture flow lives here — never hard-code these values in
/// screens, controllers or services.
///
/// Wording contract: the UI must NEVER claim "100% accurate GPS". It shows
/// the real accuracy radius (e.g. "Location accuracy: 7 m") and drives copy
/// from [AccuracyTier].
class LocationAccuracyConfig {
  LocationAccuracyConfig._();

  // ── Accuracy classification (meters) ─────────────────────────────────────
  /// <= 5 m — excellent
  static const double excellentMaxMeters = 5;

  /// <= 10 m — good
  static const double goodMaxMeters = 10;

  /// <= 25 m — acceptable
  static const double acceptableMaxMeters = 25;

  /// <= 50 m — weak (usable with a warning)
  static const double weakMaxMeters = 50;

  /// > 50 m — poor: discard during best-reading selection.
  static const double discardAboveMeters = 50;

  /// Acquisition stops early once a reading reaches this accuracy.
  static const double targetAccuracyMeters = 10;

  /// Below this the final confirmation is blocked ("not accurate enough").
  static const double minimumUsableAccuracyMeters = 50;

  // ── Timing ────────────────────────────────────────────────────────────────
  /// Overall acquisition window (STEP 1 + STEP 2 combined budget).
  static const Duration acquisitionTimeout = Duration(seconds: 20);

  /// Per-reading high-accuracy fix limit.
  static const Duration singleReadingTimeLimit = Duration(seconds: 10);

  /// A reading older than this is stale and must be re-fetched before use.
  static const Duration locationMaxAge = Duration(seconds: 30);

  /// Delay between progressive accuracy-improvement UI updates.
  static const Duration readingUiThrottle = Duration(milliseconds: 250);

  // ── Map / pin behaviour ───────────────────────────────────────────────────
  /// Initial camera zoom when centering on the device location.
  static const double initialMapZoom = 17;

  /// Zoom used when there is neither a GPS fix nor a pin yet (map-only mode):
  /// the shopkeeper pans/zooms to their shop.
  static const double overviewMapZoom = 5;

  /// If the shop pin is moved further than this from the device GPS fix,
  /// the shopkeeper must explicitly confirm ("Are you sure this is your shop?").
  static const double pinDriftWarningMeters = 150;

  /// Distance filter (meters) for the improvement stream.
  static const int streamDistanceFilterMeters = 5;

  // ── geolocator mapping ────────────────────────────────────────────────────
  /// Highest accuracy the device supports.
  static const LocationAccuracy geolocatorAccuracy =
      LocationAccuracy.bestForNavigation;

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Classifies an accuracy radius into a UI tier.
  static AccuracyTier tierFor(double? accuracy) {
    if (accuracy == null || accuracy < 0) return AccuracyTier.unknown;
    if (accuracy <= excellentMaxMeters) return AccuracyTier.excellent;
    if (accuracy <= goodMaxMeters) return AccuracyTier.good;
    if (accuracy <= acceptableMaxMeters) return AccuracyTier.acceptable;
    if (accuracy <= weakMaxMeters) return AccuracyTier.weak;
    return AccuracyTier.poor;
  }

  /// True when [timestamp] is older than [locationMaxAge].
  static bool isStale(DateTime timestamp, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    return reference.difference(timestamp) > locationMaxAge;
  }

  /// "Location accuracy: 7 m" — never "100% accurate".
  static String accuracyLabel(double? accuracy) {
    final tier = tierFor(accuracy);
    if (tier == AccuracyTier.unknown) return 'Accuracy unknown';
    final meters = accuracy!.round();
    return 'Accuracy: $meters m';
  }

  /// Short quality word shown next to the accuracy value.
  static String tierLabel(AccuracyTier tier) => switch (tier) {
        AccuracyTier.excellent => 'Excellent',
        AccuracyTier.good => 'Good',
        AccuracyTier.acceptable => 'Fair',
        AccuracyTier.weak => 'Weak',
        AccuracyTier.poor => 'Poor',
        AccuracyTier.unknown => 'Measuring…',
      };
}
