import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/restaurants/data/menu_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/restaurants/domain/menu_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/restaurants/presentation/menu_management_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/shop_models.dart';

import 'fakes.dart';

/// A repository stub, so these tests exercise the screen rather than HTTP.
class _FakeMenuRepository implements MenuRepository {
  _FakeMenuRepository({this.profileThrows = false});

  bool profileThrows;
  List<RestaurantMenuCategory> categories = const [];
  final List<String> calls = [];

  @override
  Future<MyRestaurant> restaurantForShop(int shopId, {String? token}) async {
    calls.add('restaurantForShop');
    if (profileThrows) {
      throw ApiException(
        statusCode: 404,
        message: 'This shop has no restaurant profile yet',
      );
    }
    return const MyRestaurant(id: 5, shopId: 12);
  }

  @override
  Future<RestaurantMenu> fetchMenu(int restaurantId, {String? token}) async {
    calls.add('fetchMenu');
    return RestaurantMenu(restaurantId: restaurantId, categories: categories);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The screen's own honesty rules, checked at the widget level.
///
/// The menu screens must never look like they work when they do not: a shop with
/// no restaurant profile, or a menu that will not load, has to SAY so rather than
/// showing an empty list that reads as "you have no dishes".
void main() {
  Widget host(MenuRepository repository) => ProviderScope(
        overrides: [
          menuRepositoryProvider.overrideWithValue(repository),
          tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token'),
          ),
          selectedShopProvider.overrideWith(
            () => SelectedShopOverride(
              const ShopSummary(
                id: 12,
                name: 'Tandoor',
                status: 'REGISTERED',
                isVerified: false,
                category: 'RESTAURANTS',
                membership: 'owner',
                permissions: ['read:dashboard', 'update:shop'],
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: MenuManagementScreen()),
      );

  testWidgets(
    'a shop with no restaurant profile says so, and does not show an empty menu',
    (tester) async {
      final repo = _FakeMenuRepository(profileThrows: true);
      await tester.pumpWidget(host(repo));
      await tester.pumpAndSettle();

      expect(find.text('No restaurant profile yet'), findsOneWidget);
      // The backend's own wording, so the owner is not guessing.
      expect(find.text('This shop has no restaurant profile yet'), findsOneWidget);
      // Crucially: it must not claim the menu is merely empty.
      expect(find.text('Your menu is empty'), findsNothing);
    },
  );

  testWidgets('a load failure offers a retry', (tester) async {
    await tester.pumpWidget(host(_FakeMenuRepository(profileThrows: true)));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);
  });

  testWidgets('the menu is fetched through the shop lookup, never a typed id',
      (tester) async {
    final repo = _FakeMenuRepository();
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();
    // The order proves the screen resolves the restaurant from its shop id
    // rather than asking the owner for an internal id.
    expect(repo.calls.first, 'restaurantForShop');
  });
}