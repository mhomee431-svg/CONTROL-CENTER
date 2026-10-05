import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/splash/splash_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/home/presentation/screens/coming_soon_screen.dart';
import '../../features/home/presentation/screens/search_results_by_pin_screen.dart';
import '../../features/search/presentation/screens/barcode_scan_screen.dart';
import '../../features/search/presentation/screens/search_screen.dart';
import '../../features/search/presentation/screens/search_results_screen.dart';
import '../../features/saved_and_history/presentation/screens/saved_items_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/notifications/presentation/screens/notification_settings_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/profile/presentation/screens/account_screen.dart';
import '../../features/profile/presentation/screens/edit_profile_screen.dart';
import '../../features/profile/presentation/screens/legal_document_screen.dart';
import '../../features/profile/presentation/screens/privacy_screen.dart';
import '../../features/profile/presentation/screens/delete_account_screen.dart';
import '../../features/profile/presentation/screens/addresses_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/settings/presentation/screens/about_screen.dart';
import '../../features/auth/presentation/controllers/auth_controller.dart';
import '../../features/location/presentation/screens/location_settings_screen.dart';
import '../../features/location/presentation/screens/location_permission_screen.dart';
import '../../features/location/presentation/screens/select_location_screen.dart';
import '../../features/product_details/presentation/screens/product_details_screen.dart';
import '../../features/product_details/presentation/screens/nearby_shops_screen.dart';
import '../../features/shop_details/presentation/screens/shop_details_screen.dart';
import '../../features/shop_details/presentation/screens/transport_trips_screen.dart';
import '../../features/directions/presentation/screens/directions_screen.dart';
import '../../features/customer/presentation/screens/customer_favorites_screen.dart';
import '../../features/customer/presentation/screens/customer_recently_viewed_screen.dart';
import '../../features/support/presentation/screens/help_support_screen.dart';
import '../../features/support/presentation/screens/support_issues_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/otp_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/welcome_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_flow_screen.dart';
import '../../features/location/presentation/screens/map_picker_screen.dart';
import '../../features/onboarding/presentation/controllers/onboarding_controller.dart';

import '../../features/order/presentation/screens/my_orders_screen.dart';
import '../../features/order/presentation/screens/order_detail_screen.dart';
import '../../core/widgets/deep_link_unavailable_screen.dart';
import '../../features/search/presentation/controllers/search_controller.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final shellNavigatorKey = GlobalKey<NavigatorState>();

/// Screens a signed-out / expired customer may still reach.
///
/// Used by the session-expiry redirect so "your session ended" lands the
/// customer somewhere useful instead of always on a login wall. Browsing is the
/// whole point of a guest-first hyperlocal app: expiring a token should cost
/// them their saved lists, not their ability to look at shops nearby.
///
/// Exact path match, not a prefix match, because GoRouter's `matchedLocation`
/// reports the concrete path (`/shop/42`), not the pattern (`/shop/:id`). The
/// dynamic roots below are therefore matched separately, by [_isPublicLocation].
///
/// The auth flow itself is deliberately NOT public — `/login` must stay off
/// this list, or a customer already on the login screen would be bounced home
/// by the redirect before they could type their number. That is the infinite
/// redirect loop this guard exists to prevent.
const Set<String> _publicLocations = {
  '/',
  '/search',
  '/search/results',
  '/search/scan',
  '/saved',
  '/select-location',
  '/location-settings',
  '/location-permission',
  '/map-picker',
};

/// Dynamic-route roots a signed-out customer may still reach.
///
/// Split from [_publicLocations] because these are declared as `/shop/:id` and
/// resolve to `/shop/42`, which an exact set lookup would miss — and missing
/// them is what would send an expired customer browsing a shop to a login wall
/// for no reason.
const Set<String> _publicLocationPrefixes = {
  '/shop/',
  '/product/',
  '/offer/',
  '/directions',
};

bool _isPublicLocation(String location) {
  if (_publicLocations.contains(location)) return true;
  return _publicLocationPrefixes.any(location.startsWith);
}

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);
  final onboardingCompleted = ref.watch(onboardingCompletedProvider);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    redirect: (context, state) {
      final location = state.matchedLocation;
      final isGoingToSplash = location == '/splash';

      // Startup gate: splash stays visible until BOTH the persisted onboarding
      // flag and the auth status are resolved.
      if (authState.status == AuthStatus.initial ||
          onboardingCompleted == null ||
          (isGoingToSplash && authState.status == AuthStatus.loading)) {
        return isGoingToSplash ? null : '/splash';
      }

      if (isGoingToSplash) {
        return onboardingCompleted ? '/' : '/onboarding';
      }

      // A completed tour cannot be replayed by entering its URL directly.
      if (location == '/onboarding' && onboardingCompleted) {
        return '/welcome';
      }

      // First launch presents the tour before any other destination. `/welcome`
      // stays reachable so the tour's final CTA can finish it deliberately.
      if (!onboardingCompleted &&
          location != '/onboarding' &&
          location != '/welcome') {
        return '/onboarding';
      }

      // ── Session expiry: the customer was signed in and the server revoked
      // the session. The network layer already tried a safe refresh and only
      // escalated after THAT failed, so by the time this state exists there is
      // nothing left to recover and the account's private screens must not
      // keep rendering against data fetched with a dead token.
      //
      // This branch was missing entirely. `handleSessionExpired()` set
      // [AuthStatus.sessionExpired], but with no guard consuming it the router
      // left the customer wherever they were — still looking at "My Orders",
      // a profile, a saved-items list, all of which now 401 on every pull to
      // refresh, with no route to login anywhere on the screen.
      //
      // Guests are treated as signed OUT, not as expired: a guest browsing
      // `/account` is doing something legitimate and has nothing to recover.
      //
      // THE LOOP GUARD. `redirect` re-runs after every navigation, so the
      // destination must be excluded from its own rule: without the
      // `location != '/login'` check, an expired customer landing on /login
      // would be redirected back to /login forever — a screen that re-renders
      // itself until the app is killed, which is exactly the infinite loop this
      // must not have. Once the customer is already where we sent them, the
      // redirect returns null and GoRouter stops asking.
      if (authState.status == AuthStatus.sessionExpired &&
          location != '/login' &&
          location != '/otp' &&
          location != '/register' &&
          location != '/welcome') {
        return _isPublicLocation(location) ? '/' : '/login';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
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
        path: '/coming-soon',
        builder: (context, state) => const Scaffold(body: ComingSoonScreen()),
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
      // Deep-link target for `DeepLinkEntity.offer`.
      //
      // Registered so an offer link can never 404. There is no offer screen in
      // this build, so it renders the shared "not available" state; the guard
      // normally refuses these links before navigation even happens.
      GoRoute(
        path: '/offer/:id',
        builder: (context, state) => const OfferLinkScreen(),
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
        builder: (context, state) => SettingsScreen(
          initialSection: state.uri.queryParameters['section'],
        ),
      ),
      GoRoute(
        path: '/privacy',
        builder: (context, state) =>
            const LegalDocumentScreen(document: LegalDocument.privacy),
      ),
      GoRoute(
        path: '/terms',
        builder: (context, state) =>
            const LegalDocumentScreen(document: LegalDocument.terms),
      ),
      GoRoute(path: '/about', builder: (context, state) => const AboutScreen()),
      GoRoute(
        path: '/notification-settings',
        builder: (context, state) => const NotificationSettingsScreen(),
      ),
      GoRoute(
        path: '/location-settings',
        builder: (context, state) => const LocationSettingsScreen(),
      ),
      GoRoute(
        path: '/delete-account',
        builder: (context, state) => const DeleteAccountScreen(),
      ),
      GoRoute(
        // Distinct from '/privacy' (the legal document). This is the
        // interactive privacy & data centre: switches and account actions.
        path: '/privacy-data',
        builder: (context, state) => const PrivacyScreen(),
      ),
      GoRoute(
        path: '/help',
        builder: (context, state) => const HelpSupportScreen(),
      ),
      // The READ half of /help's report form: the reports a customer already
      // filed, with their real backend status. Its own route because it answers
      // a different question ("what happened to my report?") than filing one,
      // and registered directly so the answer is reachable without hunting
      // through the help tabs — the reason the ticket history went unread before
      // is that nothing pointed at it.
      GoRoute(
        path: '/support/issues',
        builder: (context, state) => const SupportIssuesScreen(),
      ),
      GoRoute(
        path: '/orders',
        builder: (context, state) => const MyOrdersScreen(),
      ),
      GoRoute(
        path: '/order/:id',
        builder: (context, state) {
          final orderId = state.pathParameters['id'] ?? '';
          return OrderDetailScreen(orderId: orderId);
        },
      ),
      // Transport trips — quotes and service bookings for the transport /
      // personal-transport categories. Deliberately a SEPARATE route from
      // '/orders': a transport booking is a service booking (Rule 6), not a
      // product order, and sharing a route would give trips order vocabulary
      // (items, delivery, stock) they do not have.
      GoRoute(
        path: '/trips',
        builder: (context, state) => const TransportTripsScreen(),
      ),
      // OTP verification — pushed by login and registration after a
      // successful sendOtp (args travel via `extra`).
      GoRoute(
        path: '/otp',
        builder: (context, state) {
          final extra = state.extra;
          final args = extra is Map<String, dynamic>
              ? extra
              : const <String, dynamic>{};
          return OtpVerificationScreen(
            phoneNumber: (args['phone'] as String?) ?? '',
            name: args['name'] as String?,
            isNewUser: (args['isNewUser'] as bool?) ?? false,
          );
        },
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingFlowScreen(),
      ),
      GoRoute(
        path: '/map-picker',
        builder: (context, state) => const MapPickerScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
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
                builder: (context, state) {
                  // Deep links land as `/search?q=dove`. The field starts
                  // empty, so the query is handed to the notifier here rather
                  // than only living in the field: suggestions and results
                  // both key off provider state, and a field-only seed would
                  // render an empty search screen until the customer tapped.
                  final query = state.uri.queryParameters['q']?.trim() ?? '';
                  if (query.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      ref.read(searchQueryProvider.notifier)
                        ..onTextChanged(query)
                        ..debouncedTextChanged(query);
                    });
                  }
                  return const SearchScreen();
                },
                routes: [
                  GoRoute(
                    path: 'results',
                    builder: (context, state) {
                      final query = state.uri.queryParameters['q'] ?? '';
                      return SearchResultsScreen(query: query);
                    },
                  ),
                  // Camera scan — pushed from the search field's scanner icon.
                  // Reached only when the entry point is offered, but the route
                  // itself stays registered so deep links and a mid-session
                  // kill-switch flip cannot strand the user on a 404 page.
                  GoRoute(
                    path: 'scan',
                    builder: (context, state) => const BarcodeScanScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/saved',
                builder: (context, state) => SavedItemsScreen(
                  // Lets the account hub deep-link straight to Saved
                  // Products / Saved Shops / Search History instead of
                  // dumping the customer on tab 0 every time.
                  initialTab: SavedItemsTab.fromQuery(
                    state.uri.queryParameters['tab'],
                  ),
                ),
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
              // The nav's "Profile" tab is the account HUB: the customer's
              // single entry point for profile, saved items, addresses,
              // notifications, settings, help and logout. The identity page
              // itself stays reachable at /profile (pushed from the hub).
              GoRoute(
                path: '/account',
                builder: (context, state) => const AccountScreen(),
              ),
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
