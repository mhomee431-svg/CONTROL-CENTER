/// Centralized Shopkeeper API endpoint definitions.
///
/// All endpoints are relative to [EnvConfig.apiBaseUrl]. The shopkeeper app
/// exclusively consumes the isolated `/shopkeeper/*` module — never the
/// customer `/auth/*` or discovery routes.
class ApiEndpoints {
  ApiEndpoints._();

  // ── Shopkeeper auth ──
  static const String sendOtp = '/api/v1/shopkeeper/auth/send-otp';
  static const String register = '/api/v1/shopkeeper/auth/register';
  static const String login = '/api/v1/shopkeeper/auth/login';
  static const String refresh = '/api/v1/shopkeeper/auth/refresh';
  static const String logout = '/api/v1/shopkeeper/auth/logout';
  static const String me = '/api/v1/shopkeeper/auth/me';

  // ── Shopkeeper portal ──
  static const String shops = '/api/v1/shopkeeper/shops';
  static String shop(String id) => '$shops/$id';
  static String shopProfile(String id) => '${shop(id)}/profile';
  static String shopSettings(String id) => '${shop(id)}/settings';
  static String dashboard(String id) => '${shop(id)}/dashboard';
  static String inventory(String id) => '${shop(id)}/inventory';
  static String products(String id) => '${shop(id)}/products';
  static String product(String shopId, String productId) =>
      '${products(shopId)}/$productId';

  // ── Phase 7 — media / S3 object storage (secure signed-upload flow) ──
  // Credentials never reach the client: the backend authorizes, mints the
  // key, and returns a short-lived presigned POST policy. The file goes
  // straight to S3, then /media/confirm verifies the stored object.
  static const String mediaUploadUrl = '/api/v1/media/upload-url';
  static const String mediaConfirm = '/api/v1/media/confirm';
  static const String mediaUrl = '/api/v1/media/url';
  static const String mediaObjects = '/api/v1/media/objects';
}
