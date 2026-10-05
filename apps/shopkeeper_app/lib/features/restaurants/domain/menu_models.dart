/// The restaurant profile this shop owns.
///
/// Only [id] is ever used by the app, and only to reach the menu routes — it is
/// resolved from the shop id and never shown to anyone.
class MyRestaurant {
  const MyRestaurant({required this.id, required this.shopId});

  factory MyRestaurant.fromJson(Map<String, dynamic> json) => MyRestaurant(
        id: menuInt(json['id']),
        shopId: menuInt(json['shop_id']),
      );

  final int id;
  final int shopId;
}

/// Lenient int parsing for a payload whose numbers may arrive as strings.
///
/// A NUMERIC database column can reach the client as either, and a menu that
/// silently loses an item because `sort_order` came back as `"3"` is worse than
/// a slightly permissive parser here.
int menuInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse('${raw ?? ''}') ?? 0;
}

/// One menu item.
///
/// [isAvailableToday] is a display flag on the dish, not stock: the menu model is
/// discovery-only and deliberately has no quantity column, so nothing here can be
/// mistaken for inventory.
class RestaurantMenuItem {
  const RestaurantMenuItem({
    required this.id,
    required this.name,
    this.description,
    this.price,
    this.menuCategoryId,
    this.veg = false,
    this.spicy = false,
    this.isAvailableToday = true,
    this.sortOrder = 0,
    this.isActive = true,
  });

  factory RestaurantMenuItem.fromJson(Map<String, dynamic> json) =>
      RestaurantMenuItem(
        id: menuInt(json['id']),
        name: (json['name'] ?? '').toString(),
        description: json['description']?.toString(),
        price: json['price'] == null ? null : double.tryParse('${json['price']}'),
        menuCategoryId: json['menu_category_id'] == null
            ? null
            : menuInt(json['menu_category_id']),
        veg: json['veg'] == true,
        spicy: json['spicy'] == true,
        isAvailableToday: json['is_available_today'] != false,
        sortOrder: menuInt(json['sort_order']),
        isActive: json['is_active'] != false,
      );

  final int id;
  final String name;
  final String? description;
  final double? price;
  final int? menuCategoryId;
  final bool veg;
  final bool spicy;
  final bool isAvailableToday;
  final int sortOrder;
  final bool isActive;

  Map<String, dynamic> toRequestJson() => {
        'name': name,
        // Trimmed, so a box holding only spaces is omitted rather than stored as
        // "   " — which would then render as a blank-looking description.
        if (description != null && description!.trim().isNotEmpty)
          'description': description!.trim(),
        if (price != null) 'price': price,
        if (menuCategoryId != null) 'menu_category_id': menuCategoryId,
        'veg': veg,
        'spicy': spicy,
        'is_available_today': isAvailableToday,
        'sort_order': sortOrder,
      };
}

/// A menu section (Starters, Mains, Desserts).
class RestaurantMenuCategory {
  const RestaurantMenuCategory({
    required this.id,
    required this.name,
    this.description,
    this.sortOrder = 0,
    this.isActive = true,
    this.items = const <RestaurantMenuItem>[],
  });

  factory RestaurantMenuCategory.fromJson(Map<String, dynamic> json) =>
      RestaurantMenuCategory(
        id: menuInt(json['id']),
        name: (json['name'] ?? '').toString(),
        description: json['description']?.toString(),
        sortOrder: menuInt(json['sort_order']),
        isActive: json['is_active'] != false,
        items: (json['items'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(RestaurantMenuItem.fromJson)
            .toList(growable: false),
      );

  final int id;
  final String name;
  final String? description;
  final int sortOrder;
  final bool isActive;
  final List<RestaurantMenuItem> items;

  Map<String, dynamic> toRequestJson() => {
        'name': name,
        if (description != null && description!.trim().isNotEmpty)
          'description': description!.trim(),
        'sort_order': sortOrder,
      };
}

/// The whole menu, as the backend returns it.
class RestaurantMenu {
  const RestaurantMenu({
    required this.restaurantId,
    required this.categories,
  });

  factory RestaurantMenu.fromJson(Map<String, dynamic> json) {
    final raw = json['categories'];
    final categories = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(RestaurantMenuCategory.fromJson)
            .toList(growable: false)
        : const <RestaurantMenuCategory>[];
    // Items may arrive nested inside each category or as a sibling `items` list.
    // Reading both means the screen renders the same menu whichever shape the
    // endpoint returned, and uncategorised dishes are never dropped.
    final loose = (json['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RestaurantMenuItem.fromJson)
        .toList(growable: false);
    final uncategorised = loose
        .where((item) => item.menuCategoryId == null)
        .toList(growable: false);
    return RestaurantMenu(
      restaurantId: menuInt(json['restaurant_id'] ?? json['id']),
      categories: uncategorised.isEmpty
          ? categories
          : [
              ...categories,
              RestaurantMenuCategory(
                id: -1,
                name: 'Other items',
                items: uncategorised,
              ),
            ],
    );
  }

  final int restaurantId;
  final List<RestaurantMenuCategory> categories;

  bool get isEmpty => categories.isEmpty;

  int get itemCount =>
      categories.fold(0, (total, category) => total + category.items.length);
}