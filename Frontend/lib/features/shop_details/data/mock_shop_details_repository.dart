import '../domain/shop_details_repository.dart';
import '../domain/models/shop_details_models.dart';

class MockShopDetailsRepository implements ShopDetailsRepository {
  @override
  Future<ShopProfile> getShopProfile(String shopId) async {
    await Future.delayed(const Duration(milliseconds: 700)); // Network simulation

    if (shopId == 'error') throw Exception('Failed to connect to server');
    if (shopId == 'unavailable') throw Exception('Shop is temporarily unavailable or closed');

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
    );
  }

  @override
  Future<void> toggleSaveShop(String shopId, bool save) async {
    await Future.delayed(const Duration(milliseconds: 200));
  }
}