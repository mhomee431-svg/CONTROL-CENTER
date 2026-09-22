/// Central source of truth for **all** route paths used by `app_router.dart`
/// and for `context.push(...)` / `context.go(...)` calls across the app.
///
/// Why this exists (single source of truth):
///   * Every route string lives in exactly one place → a typo like
///     `'/shopp-register'` is caught by a missing-constant compile error
///     instead of a **silent** go_router failure at runtime (go_router logs a
///     no-match and the navigation simply does nothing).
///   * Navigation calls reference `Routes.products` instead of `'/products'`,
///     so grep'ing for a route's usage finds every call site.
///
/// Usage:
/// ```dart
/// // inside any widget
/// context.push(Routes.products);
/// context.go(Routes.dashboard);
/// // parameterized
/// context.push(Routes.insightsDrillDown('views'));
/// context.go(Routes.resetPasswordWithToken(token));
/// ```
///
/// The shell-tab group (`/dashboard`, `/products`, `/notifications`,
/// `/account`) is declared by the `StatefulShellRoute.indexedStack` in
/// `app_router.dart` — their path strings are the ShellTab constants below so
/// the shell's `initialLocation` and the bottom-bar `goNamed` calls stay in
/// sync.
abstract final class Routes {
  Routes._();

  // ── Auth flow ────────────────────────────────────────────────────────────
  static const splash = '/splash';
  static const welcome = '/welcome';
  static const login = '/login';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';
  static const phoneOtp = '/phone-otp';
  static String resetPasswordWithToken(String token) =>
      Uri(path: '/reset-password', queryParameters: {'token': token}).toString();

  // ── Profile / onboarding ─────────────────────────────────────────────────
  static const profileCreate = '/profile-create';
  static const profileEdit = '/profile-edit';
  static const shopRegister = '/shop-register';
  static const shops = '/shops';
  static const shopLocation = '/shop-location';

  // ── Business / shop identity ─────────────────────────────────────────────
  static const shopProfile = '/shop-profile';
  static const shopSettings = '/shop-settings';

  // ── Shell tabs (the four bottom-navigation destinations) ──────────────────
  /// These are hosted inside the `StatefulShellRoute.indexedStack`. Their
  /// paths are stable so the shell can `goNamed` to tabs and deep links land
  /// on the right tab.
  static const dashboard = '/dashboard';
  static const products = '/products';
  static const notifications = '/notifications';
  static const account = '/account';

  // ── Business features (require a selected shop) ─────────────────────────
  static const scanBarcode = '/scan-barcode';
  static const inventoryImport = '/inventory-import';
  static const offers = '/offers';
  static const pos = '/pos';
  // ── POS module (point-of-sale connector flow) ────────────────────────────
  static const posConnectionSetup = '/pos-connection-setup';
  static const posSync = '/pos-sync';
  static const posSyncProgress = '/pos-sync-progress';
  static const posSyncResult = '/pos-sync-result';
  static const posSyncHistory = '/pos-sync-history';
  static const posError = '/pos-error';
  static const insights = '/insights';
  // ── Inventory management (Inventory module) ───────────────────────────────
  static const inventoryDashboard = '/inventory-dashboard';
  static const inventoryList = '/inventory-list';
  static const lowStock = '/low-stock';
  static const outOfStock = '/out-of-stock';
  static const discontinuedStock = '/discontinued-stock';
  static const inventoryFreshness = '/inventory-freshness';
  static const inventorySyncStatus = '/inventory-sync-status';
  static const updateStock = '/update-stock';
  static const stockHistory = '/stock-history';

  // ── Pricing (Price List / Offers) ─────────────────────────────────────────
  static const priceList = '/price-list';
  static const updatePrice = '/update-price';
  static const priceHistory = '/price-history';
  static const createOffer = '/create-offer';
  static const activeOffers = '/active-offers';
  static const expiredOffers = '/expired-offers';
  static const offerDetails = '/offer-details';

  // ── Shop Profile module (Business hub) ─────────────────────────────────────
  static const shopEdit = '/shop-edit';
  static const shopBusinessInfo = '/shop-business-info';
  static const shopBusinessCategory = '/shop-business-category';
  static const shopOperatingHours = '/shop-operating-hours';
  static const shopLocationView = '/shop-location-view';
  static const shopStatus = '/shop-status';

  // ── Reports module (focused report views) ──────────────────────────────────
  static const insightsSales = '/insights-sales';
  static const insightsProducts = '/insights-products';
  static const insightsInventory = '/insights-inventory';

  // ── Import Center (Excel inventory import flow) ───────────────────────────
  static const importCenter = '/import-center';
  static const importUpload = '/import-upload';
  static const importPreview = '/import-preview';
  static const importProcessing = '/import-processing';
  static const importHistory = '/import-history';

  // ── Misc shell destinations (no shop required) ──────────────────────────
  static String insightsDrillDown(String metric) => '$insights/drill-down/$metric';

  // ── Misc shell destinations (no shop required) ──────────────────────────
  static const features = '/features';
  static const support = '/support';

  // ── Notification detail & preferences ─────────────────────────────────────
  static const notificationDetail = '/notification-detail';
  static const notificationPreferences = '/notification-preferences';

  // ── Settings module ───────────────────────────────────────────────────────
  static const accountSettings = '/account-settings';
  static const security = '/security';
  static const sessions = '/sessions';
  static const appSettings = '/app-settings';
  static const language = '/language';
  static const dataStorage = '/data-storage';
  static const notificationSettings = '/notification-settings';
  static const privacy = '/privacy';
  static const terms = '/terms';
  static const about = '/about';
  static const logoutConfirmation = '/logout-confirmation';

  // ── Support detail screens ────────────────────────────────────────────────
  static const faq = '/faq';
  static const contactSupport = '/contact-support';
  static const reportIssue = '/report-issue';

  // ── Support tickets (real intake + tracking) ─────────────────────────────
  /// The shopkeeper's own tickets with their live backend status.
  static const myTickets = '/my-tickets';

  /// One ticket, by id. Re-read from the backend on open so the status shown is
  /// the one support has actually set.
  static String supportTicketDetail(int ticketId) => '$myTickets/$ticketId';

  /// go_router path TEMPLATE for the detail route — [supportTicketDetail]
  /// produces concrete links (`/my-tickets/42`), while the route itself must be
  /// declared with a `:ticketId` segment.
  static const supportTicketDetailTemplate = '$myTickets/:ticketId';

  // ── Account-status gate (suspended / restricted) ────────────────────────
  static const accountStatus = '/account-status';

  // ── Shell-tab group, for the `StatefulShellRoute` initial location ────────
  static const shellTabPaths = [
    dashboard,
    products,
    notifications,
    account,
  ];
}
