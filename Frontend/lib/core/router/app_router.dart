import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/search/presentation/screens/search_screen.dart';
import '../../features/search/presentation/screens/search_results_screen.dart';
import '../../features/saved_and_history/presentation/screens/saved_items_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/profile/presentation/screens/edit_profile_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/otp_screen.dart';
import '../../features/auth/presentation/controllers/auth_controller.dart';
import '../../features/location/presentation/screens/location_permission_screen.dart';
import '../../features/location/presentation/screens/select_location_screen.dart';
import '../../features/location/presentation/controllers/location_controller.dart';
import '../../features/product_details/presentation/screens/product_details_screen.dart';
import '../../features/shop_details/presentation/screens/shop_details_screen.dart';
import '../../features/directions/presentation/screens/directions_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  // Watch auth state to trigger router rebuilds automatically
  final authState = ref.watch(authControllerProvider);
  // Watch location state to trigger router rebuilds automatically
  final locationState = ref.watch(locationControllerProvider);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    redirect: (context, state) {
      final isGoingToAuth = state.matchedLocation == '/login' || state.matchedLocation == '/otp';
      final isGoingToSplash = state.matchedLocation == '/splash';
      final isGoingToLocation = state.matchedLocation == '/location-permission' ||
          state.matchedLocation == '/select-location';

      if (authState.status == AuthStatus.initial || authState.status == AuthStatus.loading) {
        return isGoingToSplash ? null : '/splash';
      }

      if (authState.status == AuthStatus.unauthenticated) {
        return isGoingToAuth ? null : '/login';
      }

      if (authState.status == AuthStatus.authenticated || authState.status == AuthStatus.guest) {
        // Prevent authenticated/guest users from going back to login screen
        if (isGoingToAuth || isGoingToSplash) return '/';

        // GUEST GUARD: Prevent guests from accessing Profile or Saved items
        if (authState.status == AuthStatus.guest) {
          if (state.matchedLocation == '/profile' || state.matchedLocation == '/saved') {
            return '/login'; // Or navigate to a specific 'Login to View' bottom sheet/screen
          }
        }

        // LOCATION GUARD: If authenticated/guest, ensure location is set
        if (locationState.status != LocationStatus.success) {
          return isGoingToLocation ? null : '/location-permission';
        }
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/otp',
        builder: (context, state) => OtpVerificationScreen(phoneNumber: state.extra as String),
      ),
      GoRoute(
        path: '/location-permission',
        builder: (context, state) => const LocationPermissionScreen(),
      ),
      GoRoute(
        path: '/select-location',
        builder: (context, state) => const SelectLocationScreen(),
      ),
      GoRoute(
        path: '/product/:id',
        builder: (context, state) {
          final productId = state.pathParameters['id'] ?? '';
          return ProductDetailsScreen(productId: productId);
        },
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
          final shopName = state.uri.queryParameters['name'] ?? 'Shop Destination';
          return DirectionsScreen(shopId: shopId, shopName: shopName);
        },
      ),
      GoRoute(
        path: '/profile/edit',
        builder: (context, state) => const EditProfileScreen(),
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