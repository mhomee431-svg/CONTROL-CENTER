import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/features/restaurants/domain/menu_models.dart';

/// The menu payload parsing, which is where a schema drift would show up as a
/// silently missing dish rather than an error.
void main() {
  group('menu item parsing', () {
    test('reads every field the backend sends', () {
      final item = RestaurantMenuItem.fromJson(const {
        'id': 7,
        'restaurant_id': 3,
        'menu_category_id': 2,
        'name': 'Paneer Tikka',
        'description': 'Charred',
        'price': 240.5,
        'veg': true,
        'spicy': true,
        'is_available_today': false,
        'sort_order': 4,
        'is_active': true,
      });
      expect(item.id, 7);
      expect(item.name, 'Paneer Tikka');
      expect(item.description, 'Charred');
      expect(item.price, 240.5);
      expect(item.menuCategoryId, 2);
      expect(item.veg, isTrue);
      expect(item.spicy, isTrue);
      expect(item.isAvailableToday, isFalse);
      expect(item.sortOrder, 4);
    });

    test('a price sent as a string is still a number', () {
      // NUMERIC columns reach the client either way; losing the dish because the
      // price read back as "240.00" would be a silent data loss.
      final item = RestaurantMenuItem.fromJson(const {'id': 1, 'price': '240.00'});
      expect(item.price, 240.0);
    });

    test('absent price stays null rather than becoming zero', () {
      // Zero would be shown to a customer as a free dish.
      final item = RestaurantMenuItem.fromJson(const {'id': 1, 'name': 'Water'});
      expect(item.price, isNull);
    });

    test('an absent availability flag defaults to available', () {
      final item = RestaurantMenuItem.fromJson(const {'id': 1, 'name': 'Dal'});
      expect(item.isAvailableToday, isTrue);
    });

    test('a null category is preserved, not coerced to zero', () {
      final item = RestaurantMenuItem.fromJson(const {'id': 1, 'name': 'Extra'});
      expect(item.menuCategoryId, isNull);
    });
  });

  group('menu request bodies', () {
    test('an item omits blank optional fields instead of sending them empty', () {
      final body = const RestaurantMenuItem(
        id: 1,
        name: 'Dal',
        description: '   ',
      ).toRequestJson();
      expect(body.containsKey('description'), isFalse);
      expect(body.containsKey('price'), isFalse);
      expect(body['name'], 'Dal');
    });

    test('an item sends its flags explicitly', () {
      final body = const RestaurantMenuItem(
        id: 1,
        name: 'Dal',
        veg: true,
        spicy: false,
        isAvailableToday: false,
      ).toRequestJson();
      expect(body['veg'], isTrue);
      expect(body['spicy'], isFalse);
      expect(body['is_available_today'], isFalse);
    });

    test('a section sends its name and sort order', () {
      final body =
          const RestaurantMenuCategory(id: 0, name: 'Starters', sortOrder: 2)
              .toRequestJson();
      expect(body['name'], 'Starters');
      expect(body['sort_order'], 2);
    });
  });

  group('menu parsing', () {
    test('reads sections with their nested dishes', () {
      final menu = RestaurantMenu.fromJson(const {
        'restaurant_id': 3,
        'categories': [
          {
            'id': 1,
            'name': 'Starters',
            'sort_order': 0,
            'items': [
              {'id': 10, 'name': 'Samosa', 'price': 60},
            ],
          },
        ],
      });
      expect(menu.restaurantId, 3);
      expect(menu.categories, hasLength(1));
      expect(menu.categories.single.items.single.name, 'Samosa');
      expect(menu.itemCount, 1);
    });

    test('an empty menu is empty, not an error', () {
      final menu = RestaurantMenu.fromJson(const {
        'restaurant_id': 3,
        'categories': <dynamic>[],
      });
      expect(menu.isEmpty, isTrue);
      expect(menu.itemCount, 0);
    });

    test('a payload with no categories key is empty', () {
      expect(RestaurantMenu.fromJson(const {'restaurant_id': 1}).isEmpty, isTrue);
    });

    test('dishes sent loose, with no section, are still shown', () {
      // Dropping an uncategorised dish is worse than showing it under a heading:
      // the owner entered it and a customer would never see it otherwise.
      final menu = RestaurantMenu.fromJson(const {
        'restaurant_id': 3,
        'categories': <dynamic>[],
        'items': [
          {'id': 11, 'name': 'Takeaway Coke'},
        ],
      });
      expect(menu.itemCount, 1);
      expect(menu.categories.single.name, 'Other items');
    });
  });

  group('the restaurant lookup', () {
    test('reads both ids from the by-shop response', () {
      final restaurant =
          MyRestaurant.fromJson(const {'id': 5, 'shop_id': 12});
      expect(restaurant.id, 5);
      expect(restaurant.shopId, 12);
    });
  });
}