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
  static String resetPasswordWithToken(String token) =>
      Uri(path: '/reset-password', queryParameters: {'token': token}).toString();

  // ── Profile / onboarding ─────────────────────────────────────────────────
  static const profileCreate = '/profile-create';
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
  static const insights = '/insights';
  static String insightsDrillDown(String metric) => '$insights/drill-down/$metric';

  // ── Misc shell destinations (no shop required) ──────────────────────────
  static const features = '/features';
  static const support = '/support';

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
