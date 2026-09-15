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

  /// Delta stock adjustment with a backend audit trail.
  static String stockAdjustments(String shopId, String productId) =>
      '${product(shopId, productId)}/stock-adjustments';

  /// Inventory history for one product (movements, adjustments, price changes).
  static String productHistory(String shopId, String productId) =>
      '${product(shopId, productId)}/history';

  // ── Reports / Insights (shopkeeper analytics) ──
  // Aggregated server-side from the real analytics event stream (shop views,
  // product clicks, customer interactions, inventory freshness). Requires the
  // `dashboard:read` permission on the shop.
  //
  // `full` returns every section in ONE call (the load the Reports / Insights
  // screen performs). The granular endpoints stay available for future
  // drill-down views — nothing is computed client-side.
  static String analyticsFull(int shopId) =>
      '/api/v1/shopkeeper/shops/$shopId/analytics/full';
  static String analyticsOverview(int shopId) =>
      '/api/v1/shopkeeper/shops/$shopId/analytics/overview';
  static String analyticsViews(int shopId) =>
      '/api/v1/shopkeeper/shops/$shopId/analytics/views';
  static String analyticsClicks(int shopId) =>
      '/api/v1/shopkeeper/shops/$shopId/analytics/clicks';
  static String analyticsTopProducts(int shopId) =>
      '/api/v1/shopkeeper/shops/$shopId/analytics/top-products';
  static String analyticsTopSearches(int shopId) =>
      '/api/v1/shopkeeper/shops/$shopId/analytics/top-searches';
  static String analyticsInteractions(int shopId) =>
      '/api/v1/shopkeeper/shops/$shopId/analytics/interactions';
  static String analyticsDevices(int shopId) =>
      '/api/v1/shopkeeper/shops/$shopId/analytics/devices';
  static String analyticsHourly(int shopId) =>
      '/api/v1/shopkeeper/shops/$shopId/analytics/hourly';
  static String analyticsFreshness(int shopId) =>
      '/api/v1/shopkeeper/shops/$shopId/analytics/freshness';

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

  /// Shopkeeper-scoped offer list, optionally filtered by status
  /// (`active` | `expired` | `draft` | `scheduled`).
  static String offers(int shopId) =>
      '/api/v1/shopkeeper/shops/$shopId/offers';

  // ── Shop holidays ──
  // Date-specific closures (GET list / POST create / DELETE remove). Distinct
  // from the weekly schedule carried in `shopSettings`.
  static String shopHolidays(String id) => '${shop(id)}/holidays';
  static String shopHoliday(String id, int holidayId) =>
      '${shopHolidays(id)}/$holidayId';

  // ─ POS integration (point-of-sale connectors) ─
  // Backend exposes a full connector lifecycle: provider catalogue, integration
  // CRUD, credential/config/schedule updates, connect / disconnect / reconnect,
  // device registration, manual sync triggers, sync status and job history.
  static const String posProviders = '/api/v1/shopkeeper/pos/providers';
  static const String posRegister = '/api/v1/shopkeeper/pos/register';
  static const String posIntegrations = '/api/v1/shopkeeper/pos/integrations';

  static String posIntegration(int integrationId) =>
      '$posIntegrations/$integrationId';
  static String posCredentials(int integrationId) =>
      '${posIntegration(integrationId)}/credentials';
  static String posConfig(int integrationId) =>
      '${posIntegration(integrationId)}/config';
  static String posSchedule(int integrationId) =>
      '${posIntegration(integrationId)}/schedule';
  static String posConnect(int integrationId) =>
      '${posIntegration(integrationId)}/connect';
  static String posDisconnect(int integrationId) =>
      '${posIntegration(integrationId)}/disconnect';
  static String posReconnect(int integrationId) =>
      '${posIntegration(integrationId)}/reconnect';
  static String posDevices(int integrationId) =>
      '${posIntegration(integrationId)}/devices';
  static String posSync(int integrationId) =>
      '${posIntegration(integrationId)}/sync';
  static String posStatus(int integrationId) =>
      '${posIntegration(integrationId)}/status';
  static String posJobs(int integrationId) =>
      '${posIntegration(integrationId)}/jobs';

  static const String posJob = '/api/v1/shopkeeper/pos/jobs';
  static String posJobDetail(int jobId) => '$posJob/$jobId';
  static String posJobRetry(int jobId) => '$posJob/$jobId/retry';

  // ── Excel inventory imports (Phase 24 Part B) ──
  static String inventoryImports(int shopId) =>
      '/api/v1/shopkeeper/shops/$shopId/inventory-imports';

  static String inventoryImportJob(int shopId, int jobId) =>
      '/api/v1/shopkeeper/inventory-imports/$jobId?shop_id=$shopId';

  static String inventoryImportConfirm(int shopId, int jobId) =>
      '/api/v1/shopkeeper/inventory-imports/$jobId/confirm?shop_id=$shopId';
}
