/// Single source of truth for customer-facing business categories.
///
/// Grocery / general food must never appear here. Restaurants are allowed
/// as discovery, not delivery.
class ApprovedCategories {
  ApprovedCategories._();

  // ── Capability vocabulary (compiled fallback) ────────────────────────────
  // Mirrors `CustomerCapability` in
  // `backend/app/models/merchant_category.py`. Plain strings, not an enum,
  // because these names are a WIRE CONTRACT: they must match the backend
  // exactly, and this file is only the fallback used when a payload arrives
  // without capabilities (an older backend, or a response served from the
  // offline cache). The backend remains the source of truth.
  static const List<String> _productCapabilities = [
    'product_catalog',
    'availability',
    'contact',
    'directions',
    'ratings',
    'offers',
  ];

  /// A restaurant: a display-only menu and its business details. No product
  /// catalogue — and therefore no price/stock grid, cart, delivery or checkout.
  static const List<String> _restaurantCapabilities = [
    'menu',
    'contact',
    'directions',
    'ratings',
    'offers',
  ];

  /// Transport: a service domain. `quote_request` is granted only because the
  /// backend contract for it exists.
  static const List<String> _transportCapabilities = [
    'service_profile',
    'availability',
    'quote_request',
    'contact',
    'directions',
    'ratings',
  ];

  /// Personal transport / travel: a provider profile with a request entry point.
  static const List<String> _travelCapabilities = [
    'service_profile',
    'quote_request',
    'contact',
    'directions',
    'ratings',
  ];

  static const List<ApprovedCategory> all = [
    ApprovedCategory(
      name: 'Pharmacy & Healthcare',
      type: ApprovedCategoryType.product,
      capabilities: _productCapabilities,
    ),
    ApprovedCategory(
      name: 'Beauty & Personal Care',
      type: ApprovedCategoryType.product,
      capabilities: _productCapabilities,
    ),
    ApprovedCategory(
      name: 'Furniture & Home Care',
      type: ApprovedCategoryType.product,
      capabilities: _productCapabilities,
    ),
    ApprovedCategory(
      name: 'Household Goods',
      type: ApprovedCategoryType.product,
      capabilities: _productCapabilities,
    ),
    ApprovedCategory(
      name: 'Sports, Fitness & Outdoor',
      type: ApprovedCategoryType.product,
      capabilities: _productCapabilities,
    ),
    ApprovedCategory(
      name: 'Books, Media & Stationery',
      type: ApprovedCategoryType.product,
      capabilities: _productCapabilities,
    ),
    ApprovedCategory(
      name: 'Automotive Parts & Tools',
      type: ApprovedCategoryType.product,
      capabilities: _productCapabilities,
    ),
    ApprovedCategory(
      name: 'Hardware',
      type: ApprovedCategoryType.product,
      capabilities: _productCapabilities,
    ),
    ApprovedCategory(
      name: 'Restaurants',
      type: ApprovedCategoryType.restaurant,
      capabilities: _restaurantCapabilities,
    ),
    ApprovedCategory(
      name: 'Transport',
      type: ApprovedCategoryType.service,
      capabilities: _transportCapabilities,
    ),
    ApprovedCategory(
      name: 'Personal Transport / Personal Travel',
      type: ApprovedCategoryType.service,
      capabilities: _travelCapabilities,
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

  // ── Product discovery: what must NEVER be browsable ──────────────────────
  //
  // WHY A DENY-LIST AND NOT `isApproved`
  // ----------------------------------
  // The home feed once filtered its backend categories through `isApproved`, an
  // ALLOW-list of names. That looked correct and was actively wrong: an admin
  // publishing a new category could never surface it without shipping a new app
  // build, and nothing failed when they tried — the category simply vanished
  // from the customer's screen.
  //
  // The backend now owns visibility (`is_active` on `/home/feed`), so the client
  // only has to enforce the rules the database cannot express. A deny-list does
  // that without re-creating the allow-list: every category the platform has not
  // explicitly forbidden is browsable the moment it is published.
  //
  // These are the two exclusions stated in this file's header: grocery must never
  // appear, and restaurants are discovery rather than delivery.
  static const Set<String> _excludedFromProductBrowsing = {
    'grocery & general food',
    'restaurants',
  };

  /// Whether a backend category may appear in product discovery.
  ///
  /// Name-matched case-insensitively. Unknown names are ALLOWED by design — see
  /// the deny-list rationale above.
  static bool isProductBrowsable(String name) =>
      !_excludedFromProductBrowsing.contains(_key(name));
}

String _key(String name) => name.trim().toLowerCase();

enum ApprovedCategoryType { product, restaurant, service }

class ApprovedCategory {
  final String name;
  final ApprovedCategoryType type;

  /// The customer-facing surfaces this category may expose, as wire names.
  ///
  /// Read through [BusinessCapability] rather than compared as strings: this is
  /// the compiled fallback, and the enum is what a view switches on.
  final List<String> capabilities;

  const ApprovedCategory({
    required this.name,
    required this.type,
    this.capabilities = const [],
  });

  /// Derived from [capabilities] rather than from [type] alone, so a category
  /// whose capability set changes cannot leave this answer behind — it is the
  /// same question, asked of one source.
  bool get supportsProductInventory => capabilities.contains('product_catalog');

  bool get supportsBusinessDetails => true;

  /// Product delivery stays off for every category, restaurants included: the
  /// platform is discovery, and delivery is not a capability any category grants
  /// on its own (Master Spec §27, Rule 4).
  bool get supportsDelivery => false;
}
