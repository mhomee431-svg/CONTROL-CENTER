import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/controllers/auth_controller.dart';
import '../../features/auth/presentation/controllers/selected_shop.dart';
import '../../features/auth/presentation/screens/create_profile_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/reset_password_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/auth/presentation/screens/welcome_screen.dart';
import '../../features/account/presentation/screens/account_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/products/presentation/screens/products_screen.dart';
import '../../features/shell/shopkeeper_shell.dart';
import '../../features/shops/presentation/screens/shops_screen.dart';
import '../../features/shops/presentation/screens/shop_profile_screen.dart';
import '../../features/shops/presentation/screens/shop_settings_screen.dart';
import '../../features/shops/presentation/screens/location_capture_screen.dart';
import '../../features/shop_registration/presentation/screens/shop_registration_wizard.dart';
import '../../features/barcode/barcode_scanner_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  GoRoute buildRoute(String path, Widget Function(BuildContext, GoRouterState) b,
          {bool root = true}) =>
      GoRoute(path: path, parentNavigatorKey: root ? rootNavigatorKey : null, builder: b);

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
    initialLocation: '/splash',
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final selectedShop = ref.read(selectedShopProvider);
      final loc = state.matchedLocation;
      const authRoutes = [
        '/welcome',
        '/login',
        '/register',
        '/forgot-password',
        '/reset-password',
      ];
      final isSplash = loc == '/splash';

      if (auth.status == AuthStatus.initial || auth.isLoading) {
        if (authRoutes.contains(loc)) return null;
        return isSplash ? null : '/splash';
      }

      final signedOut = auth.status == AuthStatus.unauthenticated ||
          auth.status == AuthStatus.sessionExpired ||
          auth.status == AuthStatus.error;
      if (signedOut) {
        if (isSplash) return '/welcome';
        if (authRoutes.contains(loc)) return null;
        return '/welcome';
      }

      // ── Authenticated ──
      // Single-shop model: a profile is "complete" only once the shopkeeper
      // has registered their first shop. Incomplete → force profile creation
      // before anything else. Complete → normal dashboard guard.
      if (!auth.profileComplete) {
        if (loc == '/profile-create') return null;
        return '/profile-create';
      }

      String? guard(String target) {
        // Home (dashboard) and Account/Profile are always reachable right
        // after login — even before the first shop exists. Shop setup
        // (name, location, documents) lives under the Profile section and is
        // surfaced from the dashboard's welcome CTA, never forced at login.
        const alwaysOpen = ['/dashboard', '/account', '/shops', '/shop-register', '/profile-create'];
        if (alwaysOpen.any(target.startsWith)) return null;
        // The remaining business screens need a selected shop.
        const needsShop = [
          '/products',
          '/shop-profile',
          '/shop-settings',
          '/shop-location',
        ];
        if (!needsShop.any(target.startsWith)) return null;
        if (selectedShop != null) return null;
        // No shop yet → send them Home where the "Set up your shop" CTA is.
        return auth.shops.isEmpty ? '/dashboard' : '/shops';
      }

      if (authRoutes.contains(loc) || isSplash) {
        return guard('/dashboard') ?? '/dashboard';
      }
      return guard(loc);
    },
    routes: [
      buildRoute('/splash', (_, _) => const SplashScreen()),
      buildRoute('/welcome', (_, _) => const WelcomeScreen()),
      buildRoute('/login', (_, _) => const LoginScreen()),
      buildRoute('/register', (_, _) => const RegisterScreen()),
      buildRoute('/forgot-password', (_, _) => const ForgotPasswordScreen()),
      buildRoute('/reset-password', (context, state) {
        final token = state.uri.queryParameters['token'] ?? '';
        return ResetPasswordScreen(token: token);
      }),
      buildRoute('/profile-create', (_, _) => const CreateProfileScreen()),
      buildRoute('/shop-register', (_, _) => const ShopRegistrationWizard()),
      buildRoute('/shops', (_, _) => const ShopsScreen()),
      buildRoute('/shop-profile', (_, _) => const ShopProfileScreen()),
      buildRoute('/shop-settings', (_, _) => const ShopSettingsScreen()),
      buildRoute('/shop-location', (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return LocationCaptureScreen(shopName: extra?['shopName'] as String?);
      }),
      buildRoute('/scan-barcode', (_, _) => const BarcodeScannerScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ShopkeeperShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/dashboard',
                builder: (_, _) => const DashboardScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/products',
                builder: (_, _) => const ProductsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/account',
                builder: (_, _) => const AccountScreen()),
          ]),
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