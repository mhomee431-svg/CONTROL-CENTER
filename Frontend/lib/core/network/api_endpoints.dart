/// Centralized API endpoint definitions.
/// All endpoints are relative to the base URL from [EnvConfig.apiBaseUrl].
class ApiEndpoints {
  // --- Auth ---
  static const String sendOtp = '/auth/send-otp';
  static const String verifyOtp = '/auth/verify-otp';
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

  // --- Products ---
  static String product(String id) => '/products/$id';
  static String productShops(String id) => '/products/$id/shops';

  // --- Shops ---
  static const String nearbyShops = '/shops/nearby';
  static String shop(String id) => '/shops/$id';
  static String shopProducts(String id) => '/shops/$id/products';

  // --- Inventory ---
  static String inventoryByProduct(String id) => '/inventory/product/$id';
  static String inventoryByShop(String id) => '/inventory/shop/$id';

  // --- Search ---
  static const String searchProducts = '/search/products';
  static const String searchSuggestions = '/search/suggestions';

  // --- Saved Products ---
  static const String savedProducts = '/saved-products';
  static String savedProduct(String id) => '/saved-products/$id';

  // --- Saved Shops ---
  static const String savedShops = '/saved-shops';
  static String savedShop(String id) => '/saved-shops/$id';

  // --- Notifications ---
  static const String notifications = '/notifications';
  static String notificationRead(String id) => '/notifications/$id/read';
  static const String notificationsReadAll = '/notifications/read-all';

  // --- Profile ---
  static const String profile = '/profile';

  // --- Locations ---
  static const String nearbyLocations = '/locations/nearby';
  static const String manualLocationSearch = '/locations/manual-search';
}