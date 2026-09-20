/// Single source of truth for customer-facing business categories.
///
/// Grocery / general food must never appear here. Restaurants are allowed
/// as discovery, not delivery.
class ApprovedCategories {
  ApprovedCategories._();

  static const List<String> names = [
    'Pharmacy & Healthcare',
    'Beauty & Personal Care',
    'Furniture & Home Care',
    'Household Goods',
    'Sports, Fitness & Outdoor',
    'Books, Media & Stationery',
    'Automotive Parts & Tools',
    'Hardware',
    'Restaurants',
    'Transport',
    'Personal Transport / Personal Travel',
  ];

  static bool isApproved(String name) => names.contains(name);
}
