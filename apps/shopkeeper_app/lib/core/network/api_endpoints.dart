/// Centralized Shopkeeper API endpoint definitions.
///
/// All endpoints are relative to [EnvConfig.apiBaseUrl]. The shopkeeper app
/// exclusively consumes the isolated `/shopkeeper/*` module — never the
/// customer `/auth/*` or discovery routes.
class ApiEndpoints {
  ApiEndpoints._();

  // ── Shopkeeper auth ──
  static const String register = '/api/v1/shopkeeper/auth/register';
  static const String login = '/api/v1/shopkeeper/auth/login';
  static const String firebaseLogin = '/api/v1/shopkeeper/auth/firebase-login';
  static const String refresh = '/api/v1/shopkeeper/auth/refresh';
  static const String logout = '/api/v1/shopkeeper/auth/logout';
  static const String me = '/api/v1/shopkeeper/auth/me';
  static const String profile = '/api/v1/profile';
  static const String profileCreate = '/api/v1/shopkeeper/auth/profile-create';
  static const String googleProfile =
      '/api/v1/shopkeeper/auth/google-profile';
  static const String forgotPassword = '/api/v1/shopkeeper/auth/forgot-password';
  static const String resetPassword = '/api/v1/shopkeeper/auth/reset-password';

  // ── Location ──
  static String pincode(String code) => '/api/v1/locations/pincode/$code';


  // ── Shopkeeper portal ──
  static const String shops = '/api/v1/shopkeeper/shops';
  static String shop(String id) => '$shops/$id';
  static String shopProfile(String id) => '${shop(id)}/profile';
  static String shopLocation(String id) => '${shop(id)}/location';
  static String shopSettings(String id) => '${shop(id)}/settings';
  static String shopDocuments(String id) => '${shop(id)}/documents';
  static String dashboard(String id) => '${shop(id)}/dashboard';
  static String inventory(String id) => '${shop(id)}/inventory';
  static String products(String id) => '${shop(id)}/products';
  static String product(String shopId, String productId) =>
      '${products(shopId)}/$productId';

  // ── Merchant categories (shop-registration wizard) ──
  static const String businessCategories =
      '/api/v1/shopkeeper/businesses/categories';
  static String businessCategoryRequirements(String code) =>
      '$businessCategories/$code/requirements';
  static String shopHours(String id) => '${shop(id)}/hours';

    // ── Phase 7 — media / S3 object storage (secure signed-upload flow) ──
  // Credentials never reach the client: the backend authorizes, mints the
  // key, and returns a short-lived presigned POST policy. The file goes
  // straight to S3, then /media/confirm verifies the stored object.
  static const String mediaUploadUrl = '/api/v1/media/upload-url';
  static const String mediaConfirm = '/api/v1/media/confirm';
  static const String mediaUrl = '/api/v1/media/url';
  static const String mediaObjects = '/api/v1/media/objects';

    // ── Barcode scanning (Phase 24) ──
  // Resolve a barcode to a master product / variant for quick inventory
  // intake. Auth: Bearer token (SHOPKEEPER role).
  static String barcodeResolve(String barcode) =>
      '/api/v1/shopkeeper/barcodes/$barcode/resolve';

  // ── Shopkeeper notifications ──
  // Auth: Bearer token (SHOPKEEPER role). Paginated list scoped to a shop's
  // owner/managers — used by the Notifications screen in the shell nav.
  static String shopNotifications(int shopId) =>
      '/api/v1/shopkeeper/shops/$shopId/notifications';

  static String notificationRead(int notificationId) =>
      '/api/v1/shopkeeper/notifications/$notificationId/read';

  // ── Offers ──
  // Atomic create+link of one offer to selected shop products.
  static String assignOffer(int shopId) =>
      '/api/v1/shopkeeper/shops/$shopId/offers/assign';

  // ── Excel inventory imports (Phase 24 Part B) ──
  static String inventoryImports(int shopId) =>
      '/api/v1/shopkeeper/shops/$shopId/inventory-imports';

  static String inventoryImportJob(int shopId, int jobId) =>
      '/api/v1/shopkeeper/inventory-imports/$jobId?shop_id=$shopId';

  static String inventoryImportConfirm(int shopId, int jobId) =>
      '/api/v1/shopkeeper/inventory-imports/$jobId/confirm?shop_id=$shopId';
}
