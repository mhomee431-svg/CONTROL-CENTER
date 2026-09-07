/// Multi-provider map & location configuration (Zepto/Blinkit architecture).
///
/// ┌─────────────────────┬──────────────────────────────────────────┬──────────────┐
/// │ Tool                │ Where Used?                              │ Cost         │
/// ├─────────────────────┼──────────────────────────────────────────┼──────────────┤
/// │ Google Maps API     │ Address search, autocomplete, reverse     │ $200 free/   │
/// │                     │ geocoding (customer-facing).              │ month credit │
/// │ MapmyIndia (Mappls) │ Delivery navigation, address pinning,     │ India-       │
/// │                     │ lane-level micro-navigation.              │ specific     │
/// │                     │                                           │ pricing      │
/// │ OpenStreetMap       │ Baseline map rendering, internal          │ 100% Free    │
/// │ (Nominatim)         │ testing, fallback.                        │              │
/// └─────────────────────┴──────────────────────────────────────────┴──────────────┘
class MapProvidersConfig {
  MapProvidersConfig._();

  // ── Google Maps Platform ────────────────────────────────────────────
  // Get key: https://console.cloud.google.com → Maps SDK for Android +
  // Places API + Geocoding API → Credentials → API Key
  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: 'AIzaSyD-REPLACE_WITH_YOUR_KEY',
  );

  static bool get googleMapsEnabled =>
      googleMapsApiKey.isNotEmpty &&
      googleMapsApiKey != 'AIzaSyD-REPLACE_WITH_YOUR_KEY';

  // ── MapmyIndia (Mappls) ─────────────────────────────────────────────
  // Get key: https://www.mapmyindia.com/api → Sign up → Get API Key
  // Best for India-specific house-level addresses & delivery navigation.
  static const String mapplsApiKey = String.fromEnvironment(
    'MAPPLS_API_KEY',
    defaultValue: '',
  );
  static const String mapplsClientId = String.fromEnvironment(
    'MAPPLS_CLIENT_ID',
    defaultValue: '',
  );
  static const String mapplsClientSecret = String.fromEnvironment(
    'MAPPLS_CLIENT_SECRET',
    defaultValue: '',
  );

  static bool get mapplsEnabled => mapplsApiKey.isNotEmpty;

  // ── OpenStreetMap (Nominatim) ───────────────────────────────────────
  // Always available, 100% free, no key needed. Used as fallback.
  static bool get osmEnabled => true;

  /// Preferred provider for reverse geocoding (lat/lng → address).
  /// Order: Google (best quality) → Mappls (India-specific) → OSM (free)
  static String get preferredGeocodingProvider {
    if (googleMapsEnabled) return 'google';
    if (mapplsEnabled) return 'mappls';
    return 'osm';
  }

  /// Preferred provider for address search/autocomplete.
  static String get preferredSearchProvider {
    if (googleMapsEnabled) return 'google';
    if (mapplsEnabled) return 'mappls';
    return 'osm';
  }
}