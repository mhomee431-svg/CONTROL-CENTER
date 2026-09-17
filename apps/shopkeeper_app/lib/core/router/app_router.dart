import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/controllers/auth_controller.dart';
import '../../features/auth/presentation/controllers/selected_shop.dart';
import '../../features/auth/presentation/screens/create_profile_screen.dart';
import '../../features/auth/presentation/screens/account_status_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/reset_password_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/auth/presentation/screens/welcome_screen.dart';
import '../../features/account/presentation/screens/account_screen.dart';
import '../../features/account/presentation/screens/account_settings_screen.dart';
import '../../features/account/presentation/screens/security_screen.dart';
import '../../features/account/presentation/screens/app_settings_screen.dart';
import '../../features/account/presentation/screens/notification_settings_screen.dart';
import '../../features/account/presentation/screens/privacy_screen.dart';
import '../../features/account/presentation/screens/terms_screen.dart';
import '../../features/account/presentation/screens/about_screen.dart';
import '../../features/account/presentation/screens/logout_confirmation_screen.dart';
import '../../features/notifications/presentation/screens/notification_detail_screen.dart';
import '../../features/notifications/presentation/screens/notification_preferences_screen.dart';
import '../../features/support/presentation/screens/support_faq_screen.dart';
import '../../features/support/presentation/screens/contact_support_screen.dart';
import '../../features/support/presentation/screens/report_issue_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/products/presentation/screens/products_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/shell/shopkeeper_shell.dart';
import '../../features/shops/presentation/screens/shops_screen.dart';
import '../../features/shops/presentation/screens/shop_profile_screen.dart';
import '../../features/shops/presentation/screens/shop_settings_screen.dart';
import '../../features/shops/presentation/screens/edit_shop_screen.dart';
import '../../features/shops/presentation/screens/business_info_screen.dart';
import '../../features/shops/presentation/screens/business_category_screen.dart';
import '../../features/shops/presentation/screens/operating_hours_screen.dart';
import '../../features/shops/presentation/screens/shop_location_screen.dart';
import '../../features/shops/presentation/screens/shop_status_screen.dart';
import '../../features/shops/presentation/screens/location_capture_screen.dart';
import '../../features/shop_registration/presentation/screens/shop_registration_wizard.dart';
import '../../features/profile/presentation/screens/edit_profile_screen.dart';
import '../../features/barcode/barcode_scanner_screen.dart';
import '../../features/inventory_import/presentation/screens/inventory_import_screen.dart';
import '../../features/inventory_import/presentation/screens/import_center_screen.dart';
import '../../features/inventory_import/presentation/screens/import_history_screen.dart';
import '../../features/inventory_import/presentation/screens/import_preview_screen.dart';
import '../../features/inventory_import/presentation/screens/import_processing_screen.dart';
import '../../features/inventory_import/presentation/screens/import_upload_screen.dart';
import '../../features/inventory/presentation/screens/inventory_dashboard_screen.dart';
import '../../features/inventory/presentation/screens/inventory_list_screen.dart';
import '../../features/inventory/presentation/screens/inventory_sync_status_screen.dart';
import '../../features/inventory/presentation/screens/stock_history_screen.dart';
import '../../features/inventory/presentation/screens/update_stock_screen.dart';
import '../../features/offers/presentation/screens/offers_screen.dart';
import '../../features/pricing/presentation/screens/create_offer_screen.dart';
import '../../features/pricing/presentation/screens/offer_details_screen.dart';
import '../../features/pricing/presentation/screens/offer_list_screens.dart';
import '../../features/pricing/presentation/screens/price_history_screen.dart';
import '../../features/pricing/presentation/screens/price_list_screen.dart';
import '../../features/pricing/presentation/screens/update_price_screen.dart';
import '../../features/products/domain/product_models.dart';
import '../../features/notifications/domain/notification_models.dart';
import '../../features/offers/domain/offer_models.dart';
import '../../features/pos/presentation/screens/pos_screen.dart';
import '../../features/pos/presentation/screens/pos_connection_setup_screen.dart';
import '../../features/pos/presentation/screens/pos_error_screen.dart';
import '../../features/pos/presentation/screens/pos_sync_history_screen.dart';
import '../../features/pos/presentation/screens/pos_sync_progress_screen.dart';
import '../../features/pos/presentation/screens/pos_sync_result_screen.dart';
import '../../features/pos/presentation/screens/pos_sync_screen.dart';
import '../../features/insights/domain/insights_models.dart';
import '../../features/insights/presentation/screens/insights_drill_down_screen.dart';
import '../../features/insights/presentation/screens/insights_screen.dart';
import '../../features/shell/all_features_screen.dart';
import '../../features/support/presentation/screens/support_screen.dart';
import 'route_names.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  GoRoute buildRoute(
    String path,
    Widget Function(BuildContext, GoRouterState) b, {
    bool root = true,
  }) => GoRoute(
    path: path,
    parentNavigatorKey: root ? rootNavigatorKey : null,
    builder: b,
  );

  // IMPORTANT: the GoRouter is created exactly ONCE. We must NOT `ref.watch`
  // auth state here — that would create a new GoRouter (and reset the whole
  // navigation stack to /splash) on every auth state change (loading,
  // authenticated, etc.), which is exactly what bounced users back to
  // /welcome in the middle of the register/login flow.
  //
  // Instead:
  //  - `ref.read(...)` inside the redirect closure always reads the CURRENT
  //    auth / selected-shop values.
  //  - `ref.listen(...) -> router.refresh()` re-evaluates the redirect for the
  //    current location WITHOUT destroying navigation state.
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.splash,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final selectedShop = ref.read(selectedShopProvider);
      final loc = state.matchedLocation;
      const authRoutes = [
        Routes.welcome,
        Routes.login,
        Routes.register,
        Routes.forgotPassword,
        Routes.resetPassword,
      ];
      final isSplash = loc == Routes.splash;

      // ── Startup / splash hold ─────────────────────────────────────────
      // Flutter + Firebase are initialized (main), but the SESSION state is
      // not yet known (or a startup check failed and is being retried).
      // Home must NEVER render before the account state is known — hold the
      // splash instead of flickering to Welcome and back.
      if (auth.status == AuthStatus.initial ||
          auth.isLoading ||
          auth.status == AuthStatus.sessionError) {
        if (authRoutes.contains(loc)) return null;
        return isSplash ? null : Routes.splash;
      }

      final signedOut =
          auth.status == AuthStatus.unauthenticated ||
          auth.status == AuthStatus.sessionExpired ||
          auth.status == AuthStatus.error;
      if (signedOut) {
        if (isSplash) return Routes.welcome;
        if (authRoutes.contains(loc)) return null;
        return Routes.welcome;
      }

      // ── Phase 23: account restricted (inactive/suspended/banned) ──
      // The ONLY reachable destination is the account-status screen.
      if (auth.status == AuthStatus.accountRestricted) {
        return loc == Routes.accountStatus ? null : Routes.accountStatus;
      }

      // ── SHOPKEEPER access gate ────────────────────────────────────────
      // A confirmed NON-shopkeeper account must not reach any shopkeeper
      // screen. Tri-state ([AuthState.isShopkeeper]): `null` = unknown —
      // the login response omits the flag, so we stay permissive and let
      // the authoritative `/auth/me` session refresh settle it; `false` =
      // confirmed non-shopkeeper → the ONLY reachable destination is the
      // account-status dead-end (same UX as a suspended account).
      if (auth.status == AuthStatus.authenticated &&
          auth.isShopkeeper == false &&
          loc != Routes.accountStatus) {
        return Routes.accountStatus;
      }

      // ── Authenticated ──
      // Phase 23: profile does NOT exist → Create Profile. Every other
      // authenticated destination waits until the first shop exists.
      if (!auth.profileComplete) {
        return loc == Routes.profileCreate ? null : Routes.profileCreate;
      }
      // Profile exists → Shopkeeper Home; the create screen is finished.
      if (loc == Routes.profileCreate) return Routes.dashboard;
      String? guard(String target) {
        // Home (dashboard) and Account/Profile are always reachable right
        // after login — even before the first shop exists. Shop setup
        // (name, location, documents) lives under the Profile section and is
        // surfaced from the dashboard's welcome CTA, never forced at login.
        const alwaysOpen = [
          Routes.dashboard,
          Routes.account,
          Routes.shops,
          Routes.shopRegister,
          Routes.profileCreate,
          Routes.notifications,
          Routes.scanBarcode,
          Routes.support,
          // "All features" hub — navigation only, so it never needs a shop.
          Routes.features,
        ];
        if (alwaysOpen.any(target.startsWith)) return null;
        // The remaining business screens need a selected shop.
        const needsShop = [
          Routes.products,
          Routes.shopProfile,
          Routes.shopSettings,
          Routes.shopLocation,
          Routes.inventoryImport,
          Routes.offers,
          Routes.pos,
          Routes.insights,
          // Shop Profile module sub-screens (hub tiles).
          Routes.shopEdit,
          Routes.shopBusinessInfo,
          Routes.shopBusinessCategory,
          Routes.shopOperatingHours,
          Routes.shopLocationView,
          Routes.shopStatus,
        ];
        if (!needsShop.any(target.startsWith)) return null;
        if (selectedShop != null) return null;
        // No shop yet → send them Home where the "Set up your shop" CTA is.
        return auth.shops.isEmpty ? Routes.dashboard : Routes.shops;
      }

      if (authRoutes.contains(loc) || isSplash) {
        return guard(Routes.dashboard) ?? Routes.dashboard;
      }
      return guard(loc);
    },
    routes: [
      buildRoute(Routes.splash, (_, _) => const SplashScreen()),
      buildRoute(Routes.welcome, (_, _) => const WelcomeScreen()),
      buildRoute(Routes.login, (_, _) => const LoginScreen()),
      buildRoute(Routes.register, (_, _) => const RegisterScreen()),
      buildRoute(Routes.forgotPassword, (_, _) => const ForgotPasswordScreen()),
      buildRoute(Routes.resetPassword, (context, state) {
        final token = state.uri.queryParameters['token'] ?? '';
        return ResetPasswordScreen(token: token);
      }),
      buildRoute(Routes.profileCreate, (_, _) => const CreateProfileScreen()),
      buildRoute(Routes.profileEdit, (_, _) => const EditProfileScreen()),
      buildRoute(Routes.accountStatus, (_, _) => const AccountStatusScreen()),
      buildRoute(Routes.shopRegister, (_, _) => const ShopRegistrationWizard()),
      buildRoute(Routes.shops, (_, _) => const ShopsScreen()),
      buildRoute(Routes.shopProfile, (_, _) => const ShopProfileScreen()),
      buildRoute(Routes.shopSettings, (_, _) => const ShopSettingsScreen()),
      // ── Shop Profile module sub-screens (hub tiles → these routes) ────────
      buildRoute(Routes.shopEdit, (_, _) => const EditShopScreen()),
      buildRoute(Routes.shopBusinessInfo, (_, _) => const BusinessInfoScreen()),
      buildRoute(
          Routes.shopBusinessCategory, (_, _) => const BusinessCategoryScreen()),
      buildRoute(
          Routes.shopOperatingHours, (_, _) => const OperatingHoursScreen()),
      buildRoute(Routes.shopLocationView, (_, _) => const ShopLocationScreen()),
      buildRoute(Routes.shopStatus, (_, _) => const ShopStatusScreen()),
      buildRoute(Routes.shopLocation, (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return LocationCaptureScreen(shopName: extra?['shopName'] as String?);
      }),
      buildRoute(Routes.scanBarcode, (_, _) => const BarcodeScannerScreen()),
      buildRoute(Routes.inventoryImport, (_, _) => const InventoryImportScreen()),
      buildRoute(Routes.inventoryDashboard, (_, _) => const InventoryDashboardScreen()),
      buildRoute(Routes.inventoryList, (_, _) => const InventoryScopeScreen(scope: InventoryScope.all)),
      buildRoute(Routes.lowStock, (_, _) => const InventoryScopeScreen(scope: InventoryScope.low)),
      buildRoute(Routes.outOfStock, (_, _) => const InventoryScopeScreen(scope: InventoryScope.outOfStock)),
      buildRoute(Routes.inventoryFreshness, (_, _) => const InventoryScopeScreen(scope: InventoryScope.freshness)),
      buildRoute(Routes.inventorySyncStatus, (_, _) => const InventorySyncStatusScreen()),
      buildRoute(Routes.updateStock, (context, state) {
        final extra = state.extra;
        return UpdateStockScreen(
          product: extra is ShopProductItem ? extra : null,
        );
      }),
      buildRoute(Routes.stockHistory, (context, state) {
        final extra = state.extra;
        return StockHistoryScreen(
          product: extra is ShopProductItem ? extra : null,
        );
      }),
      buildRoute(Routes.priceList, (_, _) => const PriceListScreen()),
      buildRoute(Routes.updatePrice, (context, state) {
        final extra = state.extra;
        return UpdatePriceScreen(
          product: extra is ShopProductItem ? extra : null,
        );
      }),
      buildRoute(Routes.priceHistory, (context, state) {
        final extra = state.extra;
        return PriceHistoryScreen(
          product: extra is ShopProductItem ? extra : null,
        );
      }),
      buildRoute(Routes.createOffer, (_, _) => const CreateOfferScreen()),
      buildRoute(Routes.activeOffers, (_, _) => const ActiveOffersScreen()),
      buildRoute(Routes.expiredOffers, (_, _) => const ExpiredOffersScreen()),
      buildRoute(Routes.offerDetails, (context, state) {
        final extra = state.extra;
        return OfferDetailsScreen(offer: extra as OfferSummary);
      }),
      buildRoute(Routes.importCenter, (_, _) => const ImportCenterScreen()),
      buildRoute(Routes.importUpload, (_, _) => const ImportUploadScreen()),
      buildRoute(Routes.importPreview, (_, _) => const ImportPreviewScreen()),
      buildRoute(Routes.importProcessing, (_, _) => const ImportProcessingScreen()),
      buildRoute(Routes.importHistory, (_, _) => const ImportHistoryScreen()),
      buildRoute(Routes.offers, (_, _) => const OffersScreen()),
      buildRoute(Routes.pos, (_, _) => const PosScreen()),
      buildRoute(
        Routes.posConnectionSetup,
        (_, _) => const PosConnectionSetupScreen(),
      ),
      buildRoute(Routes.posSync, (_, _) => const PosSyncScreen()),
      buildRoute(
        Routes.posSyncProgress,
        (_, _) => const PosSyncProgressScreen(),
      ),
      buildRoute(Routes.posSyncResult, (_, _) => const PosSyncResultScreen()),
      buildRoute(
        Routes.posSyncHistory,
        (_, _) => const PosSyncHistoryScreen(),
      ),
      buildRoute(Routes.posError, (context, state) {
        final extra = state.extra;
        return PosErrorScreen(
          message: extra is String ? extra : null,
        );
      }),
      buildRoute(Routes.insights, (_, _) => const InsightsScreen()),
      GoRoute(
        path: Routes.insightsDrillDown(':metric'),
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => InsightsDrillDownScreen(
          metric: DrillDownMetricX.fromRoute(
            state.pathParameters['metric'],
          ),
        ),
      ),
      buildRoute(Routes.features, (_, _) => const AllFeaturesScreen()),
      buildRoute(Routes.support, (_, _) => const SupportScreen()),

      // ── Notification detail & preferences ─────────────────────────────────
      buildRoute(
        Routes.notificationDetail,
        (context, state) {
          // `extra` is optional: a cold-start deep link arrives without the
          // row, and the screen renders an empty state instead of crashing.
          final extra = state.extra;
          return NotificationDetailScreen(
            notification: extra is ShopkeeperNotification ? extra : null,
          );
        },
      ),
      buildRoute(Routes.notificationPreferences, (_, _) =>
          const NotificationPreferencesScreen()),

      // ── Settings module ───────────────────────────────────────────────────
      buildRoute(Routes.accountSettings, (_, _) => const AccountSettingsScreen()),
      buildRoute(Routes.security, (_, _) => const SecurityScreen()),
      buildRoute(Routes.appSettings, (_, _) => const AppSettingsScreen()),
      buildRoute(
          Routes.notificationSettings, (_, _) =>
          const NotificationSettingsScreen()),
      buildRoute(Routes.privacy, (_, _) => const PrivacyScreen()),
      buildRoute(Routes.terms, (_, _) => const TermsScreen()),
      buildRoute(Routes.about, (_, _) => const AboutScreen()),
      buildRoute(
          Routes.logoutConfirmation, (_, _) => const LogoutConfirmationScreen()),

      // ── Support detail screens ────────────────────────────────────────────
      buildRoute(Routes.faq, (_, _) => const SupportFaqScreen()),
      buildRoute(Routes.contactSupport, (_, _) => const ContactSupportScreen()),
      buildRoute(Routes.reportIssue, (_, _) => const ReportIssueScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ShopkeeperShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.dashboard,
                builder: (_, _) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.products,
                builder: (_, _) => const ProductsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.notifications,
                builder: (_, _) => const NotificationsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.account,
                builder: (_, _) => const AccountScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  // Re-evaluate the redirect whenever auth or the selected shop changes —
  // WITHOUT recreating the router (which would reset navigation state and
  // bounce users out of the register/login flow).
  ref.listen(authControllerProvider, (_, _) => router.refresh());
  ref.listen(selectedShopProvider, (_, _) => router.refresh());

  return router;
});
