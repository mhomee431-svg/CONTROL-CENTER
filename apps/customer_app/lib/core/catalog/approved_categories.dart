/// Single source of truth for customer-facing business categories.
///
/// Grocery / general food must never appear here. Restaurants are allowed
/// as discovery, not delivery.
class ApprovedCategories {
  ApprovedCategories._();

  static const List<ApprovedCategory> all = [
    ApprovedCategory(
      name: 'Pharmacy & Healthcare',
      type: ApprovedCategoryType.product,
    ),
    ApprovedCategory(
      name: 'Beauty & Personal Care',
      type: ApprovedCategoryType.product,
    ),
    ApprovedCategory(
      name: 'Furniture & Home Care',
      type: ApprovedCategoryType.product,
    ),
    ApprovedCategory(
      name: 'Household Goods',
      type: ApprovedCategoryType.product,
    ),
    ApprovedCategory(
      name: 'Sports, Fitness & Outdoor',
      type: ApprovedCategoryType.product,
    ),
    ApprovedCategory(
      name: 'Books, Media & Stationery',
      type: ApprovedCategoryType.product,
    ),
    ApprovedCategory(
      name: 'Automotive Parts & Tools',
      type: ApprovedCategoryType.product,
    ),
    ApprovedCategory(name: 'Hardware', type: ApprovedCategoryType.product),
    ApprovedCategory(
      name: 'Restaurants',
      type: ApprovedCategoryType.restaurant,
    ),
    ApprovedCategory(name: 'Transport', type: ApprovedCategoryType.service),
    ApprovedCategory(
      name: 'Personal Transport / Personal Travel',
      type: ApprovedCategoryType.service,
    ),
  ];

  static List<String> get names =>
      all.map((category) => category.name).toList();

  static ApprovedCategory? find(String name) {
    for (final category in all) {
      if (category.name == name) return category;
    }
    return null;
  }

  static bool isApproved(String name) => find(name) != null;

  static bool isService(String name) =>
      find(name)?.type == ApprovedCategoryType.service;

  static bool isRestaurant(String name) =>
      find(name)?.type == ApprovedCategoryType.restaurant;
}

enum ApprovedCategoryType { product, restaurant, service }

class ApprovedCategory {
  final String name;
  final ApprovedCategoryType type;

  const ApprovedCategory({required this.name, required this.type});

  bool get supportsProductInventory => type == ApprovedCategoryType.product;

  bool get supportsBusinessDetails => true;

  bool get supportsDelivery => false;
}
