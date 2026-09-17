import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal_shopkeeper_app/core/auth/firebase_auth_service.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/core/router/app_router.dart';
import 'package:hyperlocal_shopkeeper_app/core/router/route_names.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/data/dashboard_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/insights/data/insights_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/data/shop_repository.dart';

import 'fakes.dart';

/// REGRESSION GUARD — every hub tile must point to a REGISTERED route.
///
/// The Shop Profile hub (`shop_profile_screen.dart`) navigates to
/// `Routes.shopEdit`, `shopBusinessInfo`, `shopBusinessCategory`,
/// `shopOperatingHours`, `shopLocationView` and `shopStatus` — but NONE of
/// those routes were registered in `app_router.dart`, and go_router silently
/// no-ops on an unknown location. The five screens existed, fully built, yet
/// every Business/Operations tile in the hub did NOTHING when tapped.
/// This test walks the live router configuration and asserts every tile's
/// destination is registered.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  GoRouter buildRouter() {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository()..restoreResult = makeSession(),
        ),
        dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepo()),
        insightsRepositoryProvider.overrideWithValue(FakeInsightsRepo()),
        shopRepositoryProvider.overrideWithValue(FakeShopRepo()),
        tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(accessToken: 'test-access-token'),
        ),
        firebaseAuthServiceProvider.overrideWithValue(FakeFirebaseAuthService()),
        selectedShopProvider.overrideWith(
          () => SelectedShopOverride(ownerShop()),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container.read(routerProvider);
  }

  /// Collects every registered GoRoute path from the live router tree,
  /// including paths inside StatefulShellRoute branches.
  Set<String> registeredPaths(GoRouter router) {
    final paths = <String>{};

    void walk(List<RouteBase> routes) {
      for (final route in routes) {
        if (route is GoRoute) {
          paths.add(route.path);
          walk(route.routes);
        } else if (route is StatefulShellRoute) {
          for (final branch in route.branches) {
            walk(branch.routes);
          }
        }
      }
    }

    walk(router.configuration.routes);
    return paths;
  }

  test('every Shop Profile hub tile destination is a registered route', () {
    final paths = registeredPaths(buildRouter());

    expect(
      paths,
      containsAll(<String>[
        Routes.shopProfile,
        Routes.shopSettings,
        Routes.shopEdit,
        Routes.shopBusinessInfo,
        Routes.shopBusinessCategory,
        Routes.shopOperatingHours,
        Routes.shopLocationView,
        Routes.shopStatus,
      ]),
      reason:
          'A hub tile points to an unregistered route - tapping it silently '
          'does nothing (go_router no-match).',
    );
  });

  test('the whole business route map is registered (no dead deep-links)', () {
    final paths = registeredPaths(buildRouter());

    expect(
      paths,
      containsAll(<String>[
        Routes.dashboard,
        Routes.products,
        Routes.notifications,
        Routes.account,
        Routes.offers,
        Routes.pos,
        Routes.insights,
        Routes.inventoryImport,
        Routes.importCenter,
        Routes.features,
        Routes.support,
      ]),
    );
  });
}
