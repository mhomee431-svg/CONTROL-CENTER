import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/splash/splash_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/home/presentation/screens/coming_soon_screen.dart';
import '../../features/home/presentation/screens/search_results_by_pin_screen.dart';
import '../../features/search/presentation/screens/search_screen.dart';
import '../../features/search/presentation/screens/search_results_screen.dart';
import '../../features/saved_and_history/presentation/screens/saved_items_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/profile/presentation/screens/edit_profile_screen.dart';
import '../../features/profile/presentation/screens/addresses_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
// ── Auth screens disabled (guest-first) ─────────────────────────────
// import '../../features/auth/presentation/screens/welcome_screen.dart';
// import '../../features/auth/presentation/screens/login_screen.dart';
// import '../../features/auth/presentation/screens/register_screen.dart';
// import '../../features/auth/presentation/screens/otp_screen.dart';
// import '../../features/onboarding/presentation/screens/onboarding_flow_screen.dart';
import '../../features/auth/presentation/controllers/auth_controller.dart';
import '../../features/location/presentation/screens/location_permission_screen.dart';
import '../../features/location/presentation/screens/select_location_screen.dart';
import '../../features/product_details/presentation/screens/product_details_screen.dart';
import '../../features/product_details/presentation/screens/nearby_shops_screen.dart';
import '../../features/shop_details/presentation/screens/shop_details_screen.dart';
import '../../features/directions/presentation/screens/directions_screen.dart';
import '../../features/customer/presentation/screens/customer_favorites_screen.dart';
import '../../features/customer/presentation/screens/customer_recently_viewed_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    redirect: (context, state) {
      final location = state.matchedLocation;
      final isGoingToSplash = location == '/splash';

      // ── Auth disabled (guest-first) ──────────────────────────────────
      // Login / register / OTP / welcome / onboarding are all commented out.
      // The customer always lands straight on the Home screen; no login wall.

      // While auth status is being resolved, show the splash screen.
      if (authState.status == AuthStatus.initial ||
          authState.status == AuthStatus.loading) {
        return isGoingToSplash ? null : '/splash';
      }

      // Every other state (guest, authenticated, etc.) → straight to Home.
      if (isGoingToSplash) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      // ── Auth routes disabled (guest-first login is off) ──────────────
      // GoRoute(path: '/welcome',
      //     builder: (context, state) => const WelcomeScreen()),
      // GoRoute(path: '/onboarding-flow',
      //     builder: (context, state) => const OnboardingFlowScreen()),
      // GoRoute(path: '/login',
      //     builder: (context, state) => const LoginScreen()),
      // GoRoute(path: '/register',
      //     builder: (context, state) => const RegisterScreen()),
      // GoRoute(path: '/otp', builder: (context, state) {
      //   final extra = state.extra;
      //   String phone = '';
      //   bool isNewUser = false;
      //   String? name;
      //   if (extra is Map<String, dynamic>) {
      //     phone = (extra['phone'] as String?) ?? '';
      //     name = extra['name'] as String?;
      //     isNewUser = (extra['isNewUser'] as bool?) ?? false;
      //   } else if (extra is String) {
      //     phone = extra;
      //   }
      //   return OtpVerificationScreen(
      //     phoneNumber: phone, name: name, isNewUser: isNewUser);
      // }),
      GoRoute(
        path: '/location-permission',
        builder: (context, state) => const LocationPermissionScreen(),
      ),
      GoRoute(
        path: '/select-location',
        builder: (context, state) => const SelectLocationScreen(),
      ),
      GoRoute(
        path: '/coming-soon',
        builder: (context, state) => const Scaffold(
          body: ComingSoonScreen(),
        ),
      ),
      GoRoute(
        path: '/search-results-by-pin/:pin',
        builder: (context, state) {
          final pin = state.pathParameters['pin'] ?? '';
          return SearchResultsByPinScreen(pin: pin);
        },
      ),
      GoRoute(
        path: '/product/:id',
        builder: (context, state) {
          final productId = state.pathParameters['id'] ?? '';
          return ProductDetailsScreen(productId: productId);
        },
        routes: [
          GoRoute(
            path: 'shops',
            builder: (context, state) {
              final productId = state.pathParameters['id'] ?? '';
              return NearbyShopsScreen(productId: productId);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/shop/:id',
        builder: (context, state) {
          final shopId = state.pathParameters['id'] ?? '';
          return ShopDetailsScreen(shopId: shopId);
        },
      ),
      GoRoute(
        path: '/directions',
        builder: (context, state) {
          final shopId = state.uri.queryParameters['shopId'] ?? '';
          final shopName =
              state.uri.queryParameters['name'] ?? 'Shop Destination';
          return DirectionsScreen(shopId: shopId, shopName: shopName);
        },
      ),
      GoRoute(
        path: '/profile/edit',
        builder: (context, state) => const EditProfileScreen(),
      ),
      GoRoute(
        path: '/profile/addresses',
        builder: (context, state) => const AddressesScreen(),
      ),
      GoRoute(
        path: '/my-favorites',
        builder: (context, state) => const CustomerFavoritesScreen(),
      ),
      GoRoute(
        path: '/recently-viewed',
        builder: (context, state) => const CustomerRecentlyViewedScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                builder: (context, state) => const SearchScreen(),
                routes: [
                  GoRoute(
                    path: 'results',
                    builder: (context, state) {
                      final query = state.uri.queryParameters['q'] ?? '';
                      return SearchResultsScreen(query: query);
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/saved',
                builder: (context, state) => const SavedItemsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/notifications',
                builder: (context, state) => const NotificationsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
