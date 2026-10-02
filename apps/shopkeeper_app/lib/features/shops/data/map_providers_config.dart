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
  // ── NO CLIENT CREDENTIALS ──────────────────────────────────────────────
  // MapmyIndia also offers an OAuth *client_credentials* flow. Those values are
  // deliberately ABSENT from this file: a client secret shipped inside an APK or
  // IPA is not a secret — it is extractable by anyone who unzips the build — and
  // the Mappls token exchange belongs on the backend, which can hold it in AWS
  // Secrets Manager. The public `mapplsApiKey` above is safe to ship because
  // Mappls restricts it by bundle/signing certificate; a client secret is not.
  //
  // Do not add MAPPLS_CLIENT_ID / MAPPLS_CLIENT_SECRET back here. `test/
  // security_testing_test.dart` fails the build if a client-secret-shaped
  // constant reappears in the frontend.
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