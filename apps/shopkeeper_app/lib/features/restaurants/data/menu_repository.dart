import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_endpoints.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_providers.dart';
import 'package:hyperlocal_shopkeeper_app/features/restaurants/domain/menu_models.dart';

/// Menu management for a restaurant.
///
/// Every route here is keyed on the SHOP id the app already holds. The backend
/// resolves the restaurant profile through the shop, so the owner is never asked
/// for an internal `restaurant_id` they never received, and the app stays
/// inside the `/shopkeeper/*` module its own contract requires.
///
/// Deliberately menu-only: there is no stock, cart or order path here, because a
/// restaurant profile is a discovery domain and adding one of those is exactly
/// the "convert to delivery" outcome the spec rules out.
class MenuRepository {
  MenuRepository({required this.client});

  final ApiClient client;

  /// Throws when the shop has no restaurant profile yet — a real state, not an
  /// error to swallow, so the screen says so rather than looping.
  Future<MyRestaurant> restaurantForShop(int shopId, {String? token}) async {
    final data = await client.get(
      ApiEndpoints.myRestaurant(shopId),
      token: token,
    );
    return MyRestaurant.fromJson(data as Map<String, dynamic>);
  }

  Future<RestaurantMenu> fetchMenu(int shopId, {String? token}) async {
    final data = await client.get(ApiEndpoints.myMenu(shopId), token: token);
    return RestaurantMenu.fromJson(data as Map<String, dynamic>);
  }

  Future<RestaurantMenuCategory> createCategory(
    int shopId,
    RestaurantMenuCategory category, {
    String? token,
  }) async {
    final data = await client.post(
      ApiEndpoints.myMenuCategories(shopId),
      body: category.toRequestJson(),
      token: token,
    );
    return RestaurantMenuCategory.fromJson(data as Map<String, dynamic>);
  }

  Future<RestaurantMenuItem> createItem(
    int shopId,
    RestaurantMenuItem item, {
    String? token,
  }) async {
    final data = await client.post(
      ApiEndpoints.myMenuItems(shopId),
      body: item.toRequestJson(),
      token: token,
    );
    return RestaurantMenuItem.fromJson(data as Map<String, dynamic>);
  }

  Future<RestaurantMenuItem> updateItem(
    int shopId,
    RestaurantMenuItem item, {
    String? token,
  }) async {
    final data = await client.put(
      ApiEndpoints.myMenuItem(shopId, item.id),
      body: item.toRequestJson(),
      token: token,
    );
    return RestaurantMenuItem.fromJson(data as Map<String, dynamic>);
  }

  /// Remove a dish from the menu.
  ///
  /// The backend soft-deletes, so a mistake is recoverable server-side; the
  /// screen still asks first, because on a published menu the change is visible
  /// to customers immediately.
  Future<void> deleteItem(int shopId, int itemId, {String? token}) async {
    await client.delete(ApiEndpoints.myMenuItem(shopId, itemId), token: token);
  }
}

final menuRepositoryProvider = Provider<MenuRepository>(
  (ref) => MenuRepository(client: ref.watch(apiClientProvider)),
);