import '../domain/product_details_repository.dart';
import '../domain/models/product_details_models.dart';

class MockProductDetailsRepository implements ProductDetailsRepository {
  @override
  Future<ProductDetails> getProductDetails(String productId) async {
    await Future.delayed(const Duration(milliseconds: 600)); // Simulate network latency

    // Simulate server error for testing resilience
    if (productId.toLowerCase() == 'error') {
      throw Exception('Simulated server error');
    }

    return ProductDetails(
      id: productId,
      name: 'Samsung Galaxy S24 Ultra 5G',
      brand: 'Samsung',
      category: 'Smartphones & Accessories',
      description: 'Dynamic AMOLED 2X display, titanium frame, Snapdragon 8 Gen 3 for Galaxy, and AI-powered proVisual engine.',
      imageUrls: [
        'https://via.placeholder.com/400',
        'https://via.placeholder.com/400?text=Back+View',
        'https://via.placeholder.com/400?text=In+Box',
      ],
      priceRange: '₹1,29,999 - ₹1,34,999',
      isAvailableAnywhere: true,
      isSaved: false,
      nearbyShopsOffers: [
        ShopOffer(
          shopId: 's1',
          shopName: 'Gupta Mobile & Electronics',
          shopImageUrl: 'https://via.placeholder.com/150',
          price: 129999,
          distanceInKm: 1.2,
          rating: 4.6,
          isAvailable: true,
          lastUpdated: DateTime.now().subtract(const Duration(minutes: 15)), // Fresh stock
          offerText: 'Free tempered glass & back cover combo',
        ),
        ShopOffer(
          shopId: 's2',
          shopName: 'Digital World Hub',
          shopImageUrl: 'https://via.placeholder.com/150',
          price: 131500,
          distanceInKm: 2.5,
          rating: 4.3,
          isAvailable: true,
          lastUpdated: DateTime.now().subtract(const Duration(hours: 4)), // Moderately fresh
        ),
        ShopOffer(
          shopId: 's3',
          shopName: 'City Electronics Outlet',
          shopImageUrl: 'https://via.placeholder.com/150',
          price: 134999,
          distanceInKm: 4.1,
          rating: 4.0,
          isAvailable: false,
          lastUpdated: DateTime.now().subtract(const Duration(hours: 36)), // Stale inventory (>24h)
        ),
      ],
    );
  }

  @override
  Future<void> toggleSaveProduct(String productId, bool save) async {
    await Future.delayed(const Duration(milliseconds: 250));
  }
}