import '../domain/product_details_repository.dart';
import '../domain/models/product_details_models.dart';

class MockProductDetailsRepository implements ProductDetailsRepository {
  /// Artificial latency, standing in for a network round trip.
  ///
  /// WHY IT IS INJECTABLE
  /// --------------------
  /// A widget test runs under Flutter's fake async, where `Future.delayed`
  /// only completes when the test explicitly advances the clock. A mock that
  /// hard-codes its latency therefore cannot reach a TERMINAL state in
  /// `pumpAndSettle`: the test pumps, the pending timer never fires, and the
  /// screen is still showing its loading skeleton when the assertions run.
  /// The result is a test that fails against correct code — it asserts on a
  /// frame that was never the product's real resting state.
  ///
  /// Passing [Duration.zero] removes the timer entirely, so the future
  /// completes in the same microtask and the screen settles on the first
  /// pump. Tests that specifically want to inspect the LOADING state pass a
  /// non-zero value and pump a bounded amount.
  ///
  /// This mirrors [MockProfileRepository.delay], which already worked this way.
  final Duration latency;

  MockProductDetailsRepository({
    this.latency = const Duration(milliseconds: 600),
  });

  /// Simulated latency, skipped entirely when zero so no timer is left
  /// pending for the test binding to trip over.
  Future<void> _simulateNetwork() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }

  @override
  Future<ProductDetails> getProductDetails(
    String productId, {
    double? radiusKm,
  }) async {
    await _simulateNetwork();

    // Simulate server error for testing resilience
    if (productId.toLowerCase() == 'error') {
      throw Exception('Simulated server error');
    }

    // Simulate empty state (no nearby shops)
    if (productId.toLowerCase() == 'empty') {
      return ProductDetails(
        product: ProductMasterDetails(
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
          mrp: 134999,
          variants: [
            const ProductVariant(
              id: 'v1',
              name: 'Titanium Black 256GB',
              sku: 'SM-S928BZKDINU',
              attributes: {'Color': 'Titanium Black', 'Storage': '256GB'},
            ),
            const ProductVariant(
              id: 'v2',
              name: 'Titanium Gray 512GB',
              sku: 'SM-S928BZGDINU',
              attributes: {'Color': 'Titanium Gray', 'Storage': '512GB'},
            ),
          ],
          attributes: [
            const ProductAttribute(
              name: 'Display',
              values: ['6.8" Dynamic AMOLED 2X'],
            ),
            const ProductAttribute(
              name: 'Processor',
              values: ['Snapdragon 8 Gen 3'],
            ),
            const ProductAttribute(
              name: 'Camera',
              values: ['200MP Main', '50MP Ultra-wide'],
            ),
            const ProductAttribute(name: 'Battery', values: ['5000 mAh']),
          ],
          identifiers: [
            const ProductIdentifier(
              type: 'EAN',
              value: '8806095393104',
              isPrimary: true,
            ),
            const ProductIdentifier(type: 'SKU', value: 'SM-S928BZKDINU'),
          ],
          isSaved: false,
        ),
        shopOffers: [],
      );
    }

    return ProductDetails(
      product: ProductMasterDetails(
        id: productId,
        name: 'Samsung Galaxy S24 Ultra 5G',
        brand: 'Samsung',
        category: 'Smartphones & Accessories',
        subcategory: 'Smartphones',
        description: 'Dynamic AMOLED 2X display, titanium frame, Snapdragon 8 Gen 3 for Galaxy, and AI-powered proVisual engine.',
        shortDescription: 'The ultimate AI smartphone with pro-grade camera.',
        baseUnit: 'piece',
        baseQuantity: 1,
        mrp: 134999,
        priceRange: '₹1,29,999 - ₹1,34,999',
        imageUrls: [
          'https://via.placeholder.com/400',
          'https://via.placeholder.com/400?text=Back+View',
          'https://via.placeholder.com/400?text=In+Box',
        ],
        variants: [
          const ProductVariant(
            id: 'v1',
            name: 'Titanium Black 256GB',
            sku: 'SM-S928BZKDINU',
            attributes: {'Color': 'Titanium Black', 'Storage': '256GB'},
          ),
          const ProductVariant(
            id: 'v2',
            name: 'Titanium Gray 512GB',
            sku: 'SM-S928BZGDINU',
            attributes: {'Color': 'Titanium Gray', 'Storage': '512GB'},
          ),
        ],
        attributes: [
          const ProductAttribute(
            name: 'Display',
            values: ['6.8" Dynamic AMOLED 2X'],
          ),
          const ProductAttribute(
            name: 'Processor',
            values: ['Snapdragon 8 Gen 3'],
          ),
          const ProductAttribute(
            name: 'Camera',
            values: ['200MP Main', '50MP Ultra-wide'],
          ),
          const ProductAttribute(name: 'Battery', values: ['5000 mAh']),
        ],
        identifiers: [
          const ProductIdentifier(
            type: 'EAN',
            value: '8806095393104',
            isPrimary: true,
          ),
          const ProductIdentifier(type: 'SKU', value: 'SM-S928BZKDINU'),
        ],
        isSaved: false,
      ),
      shopOffers: [
        ShopInventoryOffer(
          shopId: 's1',
          shopName: 'Gupta Mobile & Electronics',
          shopImageUrl: 'https://via.placeholder.com/150',
          price: 129999,
          mrp: 134999,
          distanceInKm: 1.2,
          rating: 4.6,
          isAvailable: true,
          lastUpdated: DateTime.now().subtract(
            const Duration(minutes: 15),
          ), // Fresh stock
          stockStatus: 'IN_STOCK',
          freshnessStatus: 'RECENTLY_UPDATED',
          offerText: 'Free tempered glass & back cover combo',
          isOpenNow: true,
          isAcceptingOrders: true,
        ),
        ShopInventoryOffer(
          shopId: 's2',
          shopName: 'Digital World Hub',
          shopImageUrl: 'https://via.placeholder.com/150',
          price: 131500,
          mrp: 134999,
          distanceInKm: 2.5,
          rating: 4.3,
          isAvailable: true,
          lastUpdated: DateTime.now().subtract(
            const Duration(hours: 4),
          ), // Moderately fresh
          stockStatus: 'IN_STOCK',
          freshnessStatus: 'RECENTLY_UPDATED',
          // Trading but not taking orders — a distinct, honest state.
          isOpenNow: true,
          isAcceptingOrders: false,
        ),
        ShopInventoryOffer(
          shopId: 's3',
          shopName: 'City Electronics Outlet',
          shopImageUrl: 'https://via.placeholder.com/150',
          price: 134999,
          mrp: 134999,
          distanceInKm: 4.1,
          rating: 4.0,
          isAvailable: false,
          lastUpdated: DateTime.now().subtract(
            const Duration(hours: 36),
          ), // Stale inventory (>24h)
          stockStatus: 'OUT_OF_STOCK',
          freshnessStatus: 'STALE',
          isOpenNow: false,
          isAcceptingOrders: false,
        ),
      ],
    );
  }

  @override
  Future<void> toggleSaveProduct(String productId, bool save) async {
    await Future.delayed(const Duration(milliseconds: 250));
  }
}
