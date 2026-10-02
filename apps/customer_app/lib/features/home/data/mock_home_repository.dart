import '../domain/home_repository.dart';
import '../domain/models/home_data.dart';
import '../../../core/catalog/approved_categories.dart';

class MockHomeRepository implements HomeRepository {
  /// Shared sample so the pin-search screen shows the same nearby shops the
  /// home feed serves in mock mode.
  static const List<Shop> _sampleNearbyShops = [
    Shop(
      id: 's1',
      name: 'Gupta Electronics',
      imageUrl: 'https://via.placeholder.com/300',
      distance: 1.2,
      rating: 4.5,
      isVerified: true,
    ),
    Shop(
      id: 's2',
      name: 'Sharma Hardware',
      imageUrl: 'https://via.placeholder.com/300',
      distance: 0.8,
      rating: 4.2,
      isVerified: false,
    ),
    Shop(
      id: 's3',
      name: 'Patna Medical Hall',
      imageUrl: 'https://via.placeholder.com/300',
      distance: 2.1,
      rating: 4.8,
      isVerified: true,
    ),
  ];

  @override
  Future<HomeData> fetchHomeFeed({double? latitude, double? longitude}) async {
    // Simulate network latency
    await Future.delayed(const Duration(seconds: 2));

    return HomeData(
      categories: [
        Category(
          id: '1',
          name: ApprovedCategories.names[0],
          iconUrl: 'https://via.placeholder.com/150',
        ),
        Category(
          id: '2',
          name: ApprovedCategories.names[1],
          iconUrl: 'https://via.placeholder.com/150',
        ),
        Category(
          id: '3',
          name: ApprovedCategories.names[3],
          iconUrl: 'https://via.placeholder.com/150',
        ),
        Category(
          id: '4',
          name: ApprovedCategories.names[7],
          iconUrl: 'https://via.placeholder.com/150',
        ),
      ],
      popularProducts: const [
        Product(
          id: 'p1',
          name: 'Bosch Impact Drill 13mm',
          brand: 'Bosch',
          imageUrl: 'https://via.placeholder.com/300',
          priceRange: '₹2,400 - ₹3,200',
        ),
        Product(
          id: 'p2',
          name: 'Crocin 650mg',
          brand: 'GSK',
          imageUrl: 'https://via.placeholder.com/300',
          priceRange: '₹18 - ₹35',
        ),
        Product(
          id: 'p3',
          name: 'Dettol Handwash 750ml',
          brand: 'Dettol',
          imageUrl: 'https://via.placeholder.com/300',
          priceRange: '₹99 - ₹120',
        ),
        Product(
          id: 'p4',
          name: 'Bajaj Ceiling Fan',
          brand: 'Bajaj',
          imageUrl: 'https://via.placeholder.com/300',
          priceRange: '₹1,800 - ₹2,200',
        ),
      ],
      nearbyShops: _sampleNearbyShops,
      recentSearches: const ['Paracetamol 500mg', 'Bosch Drill', 'Ceiling Fan'],
      recentlyViewed: const [
        Product(
          id: 'rv1',
          name: 'Colgate MaxFresh',
          brand: 'Colgate',
          imageUrl: 'https://via.placeholder.com/300',
          priceRange: '₹85 - ₹110',
        ),
        Product(
          id: 'rv2',
          name: 'NCERT Class 10 Book',
          brand: 'NCERT',
          imageUrl: 'https://via.placeholder.com/300',
          priceRange: '₹120 - ₹160',
        ),
      ],
      recommendedProducts: const [
        Product(
          id: 'r1',
          name: 'Nivea Body Lotion',
          brand: 'Nivea',
          imageUrl: 'https://via.placeholder.com/300',
          priceRange: '₹180 - ₹220',
        ),
        Product(
          id: 'r2',
          name: 'Yoga Mat',
          brand: 'Strauss',
          imageUrl: 'https://via.placeholder.com/300',
          priceRange: '₹499 - ₹799',
        ),
      ],
      promotions: const [
        Promotion(
          id: 'promo1',
          title: 'Monsoon Mega Sale',
          subtitle: 'Up to 40% off on hardware & appliances',
          imageUrl: 'https://via.placeholder.com/600x200',
          ctaLabel: 'Shop Now',
          ctaTarget: '/search',
        ),
        Promotion(
          id: 'promo2',
          title: 'Beauty & Personal Care',
          subtitle: 'Find nearby shops stocking everyday care brands',
          imageUrl: 'https://via.placeholder.com/600x200',
          ctaLabel: 'Explore',
          ctaTarget: '/search',
        ),
      ],
    );
  }

  @override
  Future<ShopsByPinPage> fetchShopsByPincode(
    String pincode, {
    int page = 1,
    required int limit,
  }) async {
    // Simulate network latency
    await Future.delayed(const Duration(milliseconds: 600));
    // Sliced like a real paginated endpoint, so a caller that forgets to page
    // sees fewer rows instead of the whole sample list.
    final start = (page - 1) * limit;
    if (start >= _sampleNearbyShops.length) return ShopsByPinPage.empty;
    final end = (start + limit).clamp(0, _sampleNearbyShops.length);
    final slice = _sampleNearbyShops.sublist(start, end);
    return ShopsByPinPage(
      shops: slice,
      hasMore: end < _sampleNearbyShops.length,
    );
  }
}
