import '../domain/shop_details_repository.dart';
import '../domain/models/shop_details_models.dart';

class MockShopDetailsRepository implements ShopDetailsRepository {
  @override
  Future<ShopProfile> getShopProfile(String shopId) async {
    await Future.delayed(const Duration(milliseconds: 700)); // Network simulation

    if (shopId == 'error') throw Exception('Failed to connect to server');
    if (shopId == 'unavailable') throw Exception('Shop is temporarily unavailable or closed');
    if (shopId == 'closed') {
      // A closed shop scenario for UI testing
      return ShopProfile(
        id: shopId,
        name: 'Closed Corner Store',
        imageUrl: 'https://via.placeholder.com/800x400?text=Storefront',
        rating: 3.8,
        reviewCount: 98,
        address: '12 Night Market Road, Sector 5, Downtown',
        distanceInKm: 2.5,
        openingHours: 'Mon-Sun, 9:00 AM - 9:00 PM',
        isOpenNow: false,
        phone: '+919876543211',
        about: 'A corner store that is currently closed.',
        lastInventoryUpdate: DateTime.now().subtract(const Duration(days: 1)),
        activeOffers: [],
        availableProducts: [],
        isSaved: false,
        categories: const ['Grocery', 'Stationery'],
        isVerified: true,
        latitude: 28.7150,
        longitude: 77.1150,
      );
    }
    if (shopId == 'nocoords') {
      // Shop without coordinates (coordinates unavailable case)
      return ShopProfile(
        id: shopId,
        name: 'No Coordinates Shop',
        imageUrl: 'https://via.placeholder.com/800x400?text=Storefront',
        rating: 4.2,
        reviewCount: 56,
        address: 'Hudson Lane, Guru Nanak Market',
        distanceInKm: 3.0,
        openingHours: 'Mon-Sun, 10:00 AM - 8:00 PM',
        isOpenNow: true,
        phone: '+91 9876543212',
        about: 'A shop with missing coordinates.',
        lastInventoryUpdate: DateTime.now().subtract(const Duration(hours: 1)),
        activeOffers: [],
        availableProducts: const [],
        isSaved: false,
        isVerified: false,
        latitude: 0,
        longitude: 0,
      );
    }

    return ShopProfile(
      id: shopId,
      name: 'Gupta Mobile & Electronics',
      imageUrl: 'https://via.placeholder.com/800x400?text=Storefront',
      rating: 4.6,
      reviewCount: 342,
      address: '124 Main Market, Sector 14, Downtown',
      distanceInKm: 1.2,
      openingHours: 'Mon-Sun, 10:00 AM - 9:00 PM',
      isOpenNow: true,
      phone: '+919876543210',
      about: 'Your trusted neighborhood electronics store since 2010. We deal in all major smartphone brands, accessories, and smart home devices. Best prices guaranteed.',
      lastInventoryUpdate: DateTime.now().subtract(const Duration(hours: 2)),
      activeOffers: [
        '10% instant discount on HDFC credit cards',
        'Free screen guard with every new smartphone'
      ],
      availableProducts: List.generate(6, (i) => ShopProductSummary(
        productId: 'p_$i',
        name: 'Smart Device Model $i',
        imageUrl: 'https://via.placeholder.com/200',
        price: 15000.0 + (i * 5000),
        isAvailable: i % 5 != 0, // 1 in 5 out of stock
      )),
      categories: const ['Electronics', 'Mobile Phones', 'Accessories'],
      isVerified: true,
      latitude: 28.7150,
      longitude: 77.1150,
      secondaryPhone: '+919876543219',
      email: 'care@guptamobile.example',
    );
  }

  @override
  Future<void> toggleSaveShop(String shopId, bool save) async {
    await Future.delayed(const Duration(milliseconds: 200));
  }
}