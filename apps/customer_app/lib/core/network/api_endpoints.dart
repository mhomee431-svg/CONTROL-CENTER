/// Centralized API endpoint definitions.
///
/// The API base URL ([EnvConfig.apiBaseUrl]) carries **scheme + host only**, and
/// every path below is a **bare relative path** — the versioned prefix
/// ([apiVersionPrefix]) is applied centrally by `ApiClient` via [apiPath]. Bump
/// the API version in one place here, mirroring `API_PREFIX` in
/// `backend/app/core/config.py` (`/api/v1`).
class ApiEndpoints {
  ApiEndpoints._();

  /// Versioned prefix for every backend route (FastAPI `API_PREFIX`).
  static const String apiVersionPrefix = '/api/v1';

  /// Returns [path] prefixed with the API version, unless it already carries
  /// the prefix or is an absolute URL (`http(s)://...`, e.g. a presigned S3 URL).
  static String apiPath(String path) {
    if (path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith(apiVersionPrefix)) {
      return path;
    }
    return '$apiVersionPrefix${path.startsWith('/') ? path : '/$path'}';
  }

  // --- Auth ---
  static const String sendOtp = '/auth/send-otp';
  static const String verifyOtp = '/auth/verify-otp';
  static const String googleLogin = '/auth/google-login';
  static const String register = '/auth/register';
  static const String refreshToken = '/auth/refresh';
  static const String logout = '/auth/logout';
  static const String sessions = '/auth/sessions';
  static String session(String id) => '/auth/sessions/$id';
  static const String accountStatus = '/auth/account-status';

  // --- Users ---
  static const String me = '/users/me';

  // --- Home ---
  static const String homeFeed = '/home/feed';

  // --- Categories ---
  static const String categories = '/categories';

  // --- Catalog (admin-managed master data) ---
  //
  // Public read, admin-only write. This is the SOURCE OF TRUTH for the brand
  // vocabulary used by product discovery: a hardcoded brand list in the app
  // would silently misclassify every brand added after it was written.
  static const String catalogBrands = '/catalog/brands';

  // --- Products ---
  static String product(String id) => '/products/$id';

  /// Price/availability comparison for ONE product across nearby shops
  /// (`GET /products/{identifier}/offers`). Returns the same
  /// `shop_inventories` rows that the detail payload nests, without the
  /// product-master section — for a "compare prices" view that needs only the
  /// offers. Kept as its own constant because the detail route's identifier is
  /// a PATH segment: an endpoint that took the id as a query parameter would
  /// be a different contract, not a variant of this one.
  static String productOffers(String id) => '/products/$id/offers';

  // --- Shops ---
  static const String nearbyShops = '/shops/nearby';
  static String shop(String id) => '/shops/$id';
  static String shopProducts(String id) => '/shops/$id/products';

  // --- Restaurants (Master Spec §27: discovery-only) ---
  //
  // Display-only profiles + menus. There is deliberately NO cart / checkout /
  // delivery endpoint behind them, so the app cannot grow one by accident.
  static String restaurantByShop(String shopId) =>
      '/restaurants/by-shop/$shopId';

  // --- Transport (Master Spec §28-§29: a SERVICE domain) ---
  //
  // Vehicles are NOT shop products and bookings are NOT product orders, so these
  // live here rather than under products/orders. `transportQuotes` is the only
  // customer write: a quote REQUEST, whose price comes back FROM the provider.
  static String transportProviderByShop(String shopId) =>
      '/transport/providers/by-shop/$shopId';

  /// The customer's OWN quotes — the list that carries the provider's price, so
  /// a requested quote can actually be read and then accepted.
  static const String transportQuotes = '/transport/quotes';
  static String transportQuote(String id) => '/transport/quotes/$id';
  static String transportAcceptQuote(String id) =>
      '/transport/quotes/$id/accept';

  /// The customer's own bookings, which are NOT product orders (Rule 6).
  static const String transportBookings = '/transport/bookings';
  static String transportBooking(String id) => '/transport/bookings/$id';
  static String transportCancelBooking(String id) =>
      '/transport/bookings/$id/cancel';

  // --- Inventory ---
  static String inventoryByProduct(String id) => '/inventory/product/$id';
  static String inventoryByShop(String id) => '/inventory/shop/$id';

  // --- Search ---
  // Backend serves the unified discovery engine under /search/v2/*.
  static const String searchProducts = '/search/v2/products';
  static const String searchSuggestions = '/search/v2/suggestions';
  static const String searchPopular = '/search/v2/popular';
  static const String searchHistory = '/search/v2/history';

  /// Barcode lookup — finds the shops selling the product with this barcode.
  static String searchBarcode(String barcode) => '/search/v2/barcodes/$barcode';

  // --- Saved Products ---
  static const String savedProducts = '/saved-products';
  static String savedProduct(String id) => '/saved-products/$id';

  // --- Saved Shops ---
  static const String savedShops = '/saved-shops';
  static String savedShop(String id) => '/saved-shops/$id';

  // --- Notifications (API_CONTRACT §21) ---
  static const String notifications = '/notifications';
  static String notificationRead(String id) => '/notifications/$id/read';
  static const String notificationsReadAll = '/notifications/read-all';
  static const String notificationPreferences = '/notifications/preferences';
  static const String registerDeviceToken = '/notifications/device-token';
  static String unregisterDeviceToken(String token) =>
      '/notifications/device-token/$token';

  // --- Profile ---
  static const String profile = '/profile';

  // --- Locations ---
  static const String nearbyLocations = '/locations/nearby';
  static const String manualLocationSearch = '/locations/manual-search';

  // --- Customer (favourites, recently viewed, share) ---
  static const String customerRecentlyViewed = '/customer/recently-viewed';
  static const String customerFavorites = '/customer/favorites';
  static const String customerFavoritesTypes = '/customer/favorites/types';
  static String customerProductShare(String productId) =>
      '/customer/products/$productId/share';

  // --- Support ---
  //
  // ONE path for both the customer's intake (POST) and their own report
  // history (GET). The backend deliberately serves both on `/support/issues`
  // because a ticket a customer files and the list they later read back are
  // the same resource — two constants for one path would be two places to
  // update when the route moves.
  static const String supportIssue = '/support/issues';

  // --- Orders (API_CONTRACT SS 30-32) ---
  static const String orders = '/orders';
  static String orderById(String id) => '/orders/$id';
  static String cancelOrder(String id) => '/orders/$id/cancel';
  static String updateOrderStatus(String id) => '/orders/$id/status';
  static String shopOrders(String shopId) => '/orders/shop/$shopId';
}
