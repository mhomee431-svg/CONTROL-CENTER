import '../domain/shop_details_repository.dart';
import '../domain/models/business_profile_models.dart';
import '../domain/models/shop_details_models.dart';

class MockShopDetailsRepository implements ShopDetailsRepository {
  /// Shop ids that behave as a restaurant: a menu is served for them.
  static const Set<String> restaurantShops = {'restaurant'};

  /// Shop ids that behave as a transport provider: services + fleet + a
  /// quote/write surface are served for them.
  static const Set<String> transportShops = {'transport'};

  /// Provider records published behind each transport shop, keyed by shop id.
  static const Map<String, String> providerIds = {'transport': '9001'};

  /// Quote receipts to hand back per provider id. A request is only ever
  /// CONFIRMED here — the price itself comes from the provider, never from the
  /// mock — keyed by provider id.
  final Map<String, TransportQuoteReceipt> quoteReceipts;

  MockShopDetailsRepository({
    Map<String, TransportQuoteReceipt>? quoteReceipts,
    this.latency = const Duration(milliseconds: 700),
  }) : quoteReceipts =
           quoteReceipts ??
           const {
             '9001': TransportQuoteReceipt(
               quoteId: 'Q-9001',
               status: 'REQUESTED',
             ),
           };

  /// Artificial latency for the profile read.
  ///
  /// WHY IT IS INJECTABLE
  /// --------------------
  /// Flutter widget tests run under fake async, where `Future.delayed` only
  /// completes when the test advances the clock itself. A hard-coded latency
  /// means `pumpAndSettle` returns while the screen is STILL on its loading
  /// skeleton, so an assertion about the loaded or error state fails against
  /// perfectly correct code.
  ///
  /// [Duration.zero] skips the timer outright so the future settles in the
  /// same microtask. Tests that deliberately inspect the loading state pass a
  /// non-zero value and pump a bounded amount. This mirrors
  /// [MockProfileRepository.delay].
  final Duration latency;

  /// Simulated round trip, skipped entirely when zero.
  Future<void> _simulateNetwork() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }

  @override
  Future<ShopProfile> getShopProfile(String shopId) async {
    await _simulateNetwork();

    if (shopId == 'error') throw Exception('Failed to connect to server');
    if (shopId == 'unavailable') {
      throw Exception('Shop is temporarily unavailable or closed');
    }
    if (shopId == 'restaurant') {
      // A restaurant: business details, hours and a menu — but no products,
      // no stock, and nothing that could become a cart.
      return ShopProfile(
        id: shopId,
        name: 'Annapurna Restaurant',
        imageUrl: 'https://via.placeholder.com/800x400?text=Restaurant',
        rating: 4.4,
        reviewCount: 1204,
        address: '14 Food Street, Sector 18, Downtown',
        distanceInKm: 0.8,
        openingHours: 'Mon-Sun, 11:00 AM - 11:00 PM',
        isOpenNow: true,
        phone: '+919876543220',
        about: 'Home-style North Indian meals since 1998.',
        lastInventoryUpdate: DateTime.now().subtract(const Duration(hours: 3)),
        activeOffers: const ['Free dessert on orders above ₹499 (dine-in)'],
        availableProducts: const [],
        isSaved: false,
        categories: const ['Restaurants'],
        capabilities: const [
          'menu',
          'contact',
          'directions',
          'ratings',
          'offers',
        ],
        businessCategoryName: 'Restaurants',
        businessCategoryCode: 'RESTAURANTS',
        businessType: 'Service',
        isVerified: true,
        latitude: 28.7160,
        longitude: 77.1180,
      );
    }
    if (shopId == 'transport') {
      // A transport provider: services + fleet + a request entry point — but
      // no products, and no price/stock grid.
      return ShopProfile(
        id: shopId,
        name: 'Raftaar City Movers',
        imageUrl: 'https://via.placeholder.com/800x400?text=Transport',
        rating: 4.3,
        reviewCount: 211,
        address: '23 Depot Road, Industrial Area',
        distanceInKm: 2.1,
        openingHours: 'Mon-Sat, 8:00 AM - 8:00 PM',
        isOpenNow: true,
        phone: '+919876543230',
        about: 'City rides, airport drops and family tours.',
        lastInventoryUpdate: DateTime.now().subtract(const Duration(hours: 1)),
        activeOffers: const [],
        availableProducts: const [],
        isSaved: false,
        categories: const ['Transport'],
        capabilities: const [
          'service_profile',
          'availability',
          'quote_request',
          'contact',
          'directions',
          'ratings',
        ],
        businessCategoryName: 'Transport',
        businessCategoryCode: 'TRANSPORT',
        businessType: 'Service',
        isVerified: true,
        latitude: 28.7200,
        longitude: 77.1200,
      );
    }
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
        categories: const ['Household Goods', 'Books, Media & Stationery'],
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
        'Free screen guard with every new smartphone',
      ],
      availableProducts: List.generate(
        6,
        (i) => ShopProductSummary(
          productId: 'p_$i',
          name: 'Smart Device Model $i',
          imageUrl: 'https://via.placeholder.com/200',
          price: 15000.0 + (i * 5000),
          isAvailable: i % 5 != 0, // 1 in 5 out of stock
        ),
      ),
      categories: const [
        'Hardware',
        'Household Goods',
        'Automotive Parts & Tools',
      ],
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

  @override
  Future<RestaurantProfile?> getRestaurantProfile(String shopId) async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (!restaurantShops.contains(shopId)) return null;
    return const RestaurantProfile(
      id: 'r-1',
      shopId: 'restaurant',
      name: 'Annapurna Restaurant',
      cuisineTypes: ['North Indian', 'Chinese'],
      diningAvailable: true,
      takeawayAvailable: true,
      avgCostForTwo: 600,
      rating: 4.4,
      reviewCount: 1204,
      vegOnly: false,
      phone: '+919876543220',
      address: '14 Food Street, Sector 18, Downtown',
      latitude: 28.7160,
      longitude: 77.1180,
      menu: [
        RestaurantMenuSection(
          id: 'mc-1',
          name: 'Main Course',
          description: 'Served with the bread basket of the day.',
          items: [
            RestaurantMenuItem(
              id: 'mi-1',
              name: 'Paneer Butter Masala',
              description: 'Cottage cheese in a creamy tomato gravy.',
              price: 240,
              veg: true,
            ),
            RestaurantMenuItem(
              id: 'mi-2',
              name: 'Chicken Biryani',
              description: 'Hyderabadi style, served with raita.',
              price: 280,
              spicy: true,
            ),
          ],
        ),
        RestaurantMenuSection(
          id: 'mc-2',
          name: 'Breads',
          items: [
            RestaurantMenuItem(
              id: 'mi-3',
              name: 'Butter Naan',
              price: 40,
              veg: true,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<TransportServiceProfile?> getTransportServiceProfile(
    String shopId,
  ) async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (!transportShops.contains(shopId)) return null;
    return const TransportServiceProfile(
      id: '9001',
      companyName: 'Raftaar City Movers',
      verificationStatus: 'VERIFIED',
      rating: 4.3,
      reviewCount: 211,
      vehicles: [
        ProviderVehicle(
          id: 'v-1',
          vehicleType: 'SUV',
          make: 'Toyota',
          model: 'Innova Crysta',
          registrationNumber: 'DL 1 AB 1234',
          capacityPassengers: 6,
          acAvailable: true,
        ),
        ProviderVehicle(
          id: 'v-2',
          vehicleType: 'SEDAN',
          make: 'Maruti Suzuki',
          model: 'Swift Dzire',
          registrationNumber: 'DL 1 AB 5678',
          capacityPassengers: 4,
          acAvailable: true,
        ),
      ],
      services: [
        TransportServiceOffering(
          id: 's-1',
          serviceType: 'AIRPORT',
          name: 'Airport drops',
          basePrice: 650,
          priceUnit: 'PER_TRIP',
        ),
        TransportServiceOffering(
          id: 's-2',
          serviceType: 'FAMILY_TOUR',
          name: 'Day tours',
          basePrice: 3200,
          priceUnit: 'PER_DAY',
        ),
      ],
    );
  }

  @override
  Future<TransportQuoteReceipt> requestTransportQuote(
    TransportQuoteRequest request,
  ) async {
    await Future.delayed(const Duration(milliseconds: 400));
    // A receipt, not a price: the provider quotes the amount later. An unknown
    // provider is a contract violation in the test double too, so it throws
    // rather than inventing Q-nothing.
    final receipt = quoteReceipts[request.providerId.trim()];
    if (receipt == null) {
      throw Exception('Unknown transport provider ${request.providerId}');
    }
    return receipt;
  }

  @override
  Future<TransportTrips> getMyTransportTrips() async {
    await Future.delayed(const Duration(milliseconds: 400));
    return const TransportTrips(
      quotes: [
        TransportQuote(
          id: 'Q-9001',
          providerId: '9001',
          providerName: 'Raftaar City Movers',
          // A QUOTED quote: the price exists and can be accepted, which is the
          // state the trips screen's primary action exists for.
          status: 'QUOTED',
          tripPurpose: 'AIRPORT',
          pickupAddress: 'Connaught Place',
          destinationAddress: 'IGI Airport',
          tripDate: '2026-03-07',
          tripDays: 1,
          passengerCount: 2,
          quotedAmount: 650,
        ),
        TransportQuote(
          id: 'Q-8990',
          providerId: '9001',
          providerName: 'Raftaar City Movers',
          // Still waiting on the provider: no price yet, and nothing to accept.
          status: 'REQUESTED',
          tripPurpose: 'FAMILY_TOUR',
          pickupAddress: 'Sector 18',
          destinationAddress: 'Agra',
          tripDate: '2026-04-02',
          tripDays: 2,
          passengerCount: 4,
        ),
      ],
      bookings: [
        TransportBooking(
          id: 'B-1',
          quoteId: 'Q-8900',
          bookingRef: 'TRP-7QK2M4',
          status: 'CONFIRMED',
          pickupAddress: 'Sector 18',
          destination: 'Nehru Place',
          tripDate: '2026-02-11',
          tripDays: 1,
          passengerCount: 2,
          agreedAmount: 540,
          statusHistory: [
            TransportBookingStatusEvent(toStatus: 'PENDING'),
            TransportBookingStatusEvent(
              fromStatus: 'PENDING',
              toStatus: 'CONFIRMED',
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<TransportBooking> acceptTransportQuote(String quoteId) async {
    await Future.delayed(const Duration(milliseconds: 400));
    // The booking is created by the BACKEND, so the double mints the same
    // reference the server would and never invents a price the provider did not
    // quote.
    return TransportBooking(
      id: 'B-$quoteId',
      quoteId: quoteId,
      bookingRef: 'TRP-MOCK1',
      status: 'PENDING',
      pickupAddress: 'Connaught Place',
      destination: 'IGI Airport',
      tripDate: '2026-03-07',
      tripDays: 1,
      passengerCount: 2,
      agreedAmount: 650,
      statusHistory: const [TransportBookingStatusEvent(toStatus: 'PENDING')],
    );
  }

  @override
  Future<TransportBooking> cancelTransportBooking(
    String bookingId, {
    String? reason,
  }) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return TransportBooking(
      id: bookingId,
      bookingRef: 'TRP-7QK2M4',
      status: 'CANCELLED',
      agreedAmount: 540,
    );
  }
}
