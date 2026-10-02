import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyperlocal_app/features/shop_details/data/mock_shop_details_repository.dart';
import 'package:hyperlocal_app/features/shop_details/domain/shop_details_repository.dart';
import 'package:hyperlocal_app/features/shop_details/domain/models/business_profile_models.dart';
import 'package:hyperlocal_app/features/shop_details/domain/models/shop_details_models.dart';
import 'package:hyperlocal_app/features/shop_details/presentation/screens/shop_details_screen.dart';

/// A repository returning a caller-supplied profile so each test can describe
/// exactly one profile shape (sparse contact, bad phone, missing coordinates)
/// without touching the shared mock's happy path.
class _StubShopDetailsRepository implements ShopDetailsRepository {
  _StubShopDetailsRepository(this.profile, {this.restaurant, this.service});

  final ShopProfile profile;

  /// The restaurant / provider behind this shop, when the test publishes one.
  final RestaurantProfile? restaurant;
  final TransportServiceProfile? service;

  @override
  Future<ShopProfile> getShopProfile(String shopId) async => profile;

  @override
  Future<void> toggleSaveShop(String shopId, bool save) async {}

  @override
  Future<RestaurantProfile?> getRestaurantProfile(String shopId) async =>
      restaurant;

  @override
  Future<TransportServiceProfile?> getTransportServiceProfile(
    String shopId,
  ) async => service;

  @override
  Future<TransportQuoteReceipt> requestTransportQuote(
    TransportQuoteRequest request,
  ) async => const TransportQuoteReceipt(quoteId: 'Q-1', status: 'REQUESTED');

  // A deep link never reads or changes trips: they are the customer's own,
  // account-scoped data reached only from the trips screen.
  @override
  Future<TransportTrips> getMyTransportTrips() async => const TransportTrips();

  @override
  Future<TransportBooking> acceptTransportQuote(String quoteId) async =>
      throw StateError('a deep link never accepts a quote');

  @override
  Future<TransportBooking> cancelTransportBooking(
    String bookingId, {
    String? reason,
  }) async => throw StateError('a deep link never cancels a booking');
}

ShopProfile _profile({
  String phone = '',
  String secondaryPhone = '',
  String email = '',
  double latitude = 28.7150,
  double longitude = 77.1150,
  List<ShopProductSummary> products = const [],
  List<String> capabilities = const [],
  List<String> categories = const [],
}) {
  return ShopProfile(
    id: 's1',
    name: 'Test Shop',
    imageUrl: 'https://example.com/a.jpg',
    rating: 4.2,
    reviewCount: 10,
    address: '1 Test Road',
    distanceInKm: 1.0,
    openingHours: 'Mon-Sun, 9:00 AM - 9:00 PM',
    isOpenNow: true,
    about: 'About',
    lastInventoryUpdate: DateTime.now(),
    activeOffers: const [],
    availableProducts: products,
    phone: phone,
    secondaryPhone: secondaryPhone,
    email: email,
    latitude: latitude,
    longitude: longitude,
    capabilities: capabilities,
    categories: categories,
  );
}

Widget _app(
  Widget child, {
  required ShopProfile profile,
  RestaurantProfile? restaurant,
  TransportServiceProfile? service,
}) {
  return ProviderScope(
    overrides: [
      shopDetailsRepositoryProvider.overrideWithValue(
        _StubShopDetailsRepository(
          profile,
          restaurant: restaurant,
          service: service,
        ),
      ),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('ShopDetailsScreen renders full shop profile with new fields', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shopDetailsRepositoryProvider.overrideWithValue(
            MockShopDetailsRepository(),
          ),
        ],
        child: const MaterialApp(
          home: ShopDetailsScreen(shopId: 'test_shop_1'),
        ),
      ),
    );

    // Verify loading indicator appears initially
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Wait for mock data
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Verify ShopHeader details
    expect(find.text('Gupta Mobile & Electronics'), findsOneWidget);
    expect(find.text('OPEN'), findsOneWidget);
    expect(find.textContaining('1.2 km away'), findsOneWidget);

    // Verify verification badge
    expect(find.text('Verified'), findsOneWidget);

    // Verify categories chips
    expect(find.text('Hardware'), findsOneWidget);
    expect(find.text('Household Goods'), findsOneWidget);
    expect(find.text('Automotive Parts & Tools'), findsOneWidget);

    // Verify actions exist
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Directions'), findsOneWidget);

    // Verify contact section
    expect(find.text('Contact'), findsOneWidget);
    expect(find.text('+919876543210'), findsOneWidget);

    // Verify operating hours + closed warning absent
    expect(find.text('Operating Hours'), findsOneWidget);
    expect(find.textContaining('Mon-Sun'), findsOneWidget);

    // Verify sections and trust signals
    expect(find.text('About Shop'), findsOneWidget);
    expect(find.textContaining('Inventory last updated'), findsOneWidget);

    // Verify Products Grid
    expect(find.text('Available Products'), findsOneWidget);
    expect(find.text('Smart Device Model 0'), findsOneWidget);
  });

  testWidgets('ShopDetailsScreen shows closed shop warning when not open', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shopDetailsRepositoryProvider.overrideWithValue(
            MockShopDetailsRepository(),
          ),
        ],
        child: const MaterialApp(home: ShopDetailsScreen(shopId: 'closed')),
      ),
    );

    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Closed badge and warning shown
    expect(find.text('CLOSED'), findsOneWidget);
    expect(
      find.textContaining('This shop is currently closed'),
      findsOneWidget,
    );
    expect(find.text('Closed Corner Store'), findsOneWidget);
  });

  testWidgets('ShopDetailsScreen shows coordinates unavailable warning', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shopDetailsRepositoryProvider.overrideWithValue(
            MockShopDetailsRepository(),
          ),
        ],
        child: const MaterialApp(home: ShopDetailsScreen(shopId: 'nocoords')),
      ),
    );

    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Coordinates unavailable warning shown
    expect(
      find.textContaining('Shop coordinates are temporarily unavailable'),
      findsOneWidget,
    );
    expect(find.text('No Coordinates Shop'), findsOneWidget);
  });

  testWidgets('ShopDetailsScreen handles error state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shopDetailsRepositoryProvider.overrideWithValue(
            MockShopDetailsRepository(),
          ),
        ],
        child: const MaterialApp(
          home: ShopDetailsScreen(shopId: 'error'), // Triggers mock exception
        ),
      ),
    );

    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.textContaining('Unable to load shop'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('ShopDetailsScreen icon buttons expose accessible tooltips', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shopDetailsRepositoryProvider.overrideWithValue(
            MockShopDetailsRepository(),
          ),
        ],
        child: const MaterialApp(
          home: ShopDetailsScreen(shopId: 'test_shop_1'),
        ),
      ),
    );

    // Initial state: loading indicator is shown while shop data loads.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 2));

    // After mock loads, the save and share buttons render in the app bar.
    expect(find.byTooltip('Save shop'), findsOneWidget);
    expect(find.byTooltip('Share shop'), findsOneWidget);
  });

  group('optional contact metadata', () {
    testWidgets('renders secondary phone and email when provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const ShopDetailsScreen(shopId: 's1'),
          profile: _profile(
            phone: '+91 98765 43210',
            secondaryPhone: '+91 98765 43219',
            email: 'care@example.com',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('+91 98765 43210'), findsOneWidget);
      expect(find.text('+91 98765 43219'), findsOneWidget);
      expect(find.text('care@example.com'), findsOneWidget);
    });

    testWidgets('omits absent optional fields instead of showing blanks', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const ShopDetailsScreen(shopId: 's1'),
          profile: _profile(phone: '+919876543210'),
        ),
      );
      await tester.pumpAndSettle();

      // Only the primary number is listed; no empty rows are rendered.
      expect(find.text('+919876543210'), findsOneWidget);
      expect(find.text('No contact info available'), findsNothing);
    });

    testWidgets('shows an explicit empty state when no contact data exists', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const ShopDetailsScreen(shopId: 's1'), profile: _profile()),
      );
      await tester.pumpAndSettle();

      expect(find.text('No contact info available'), findsOneWidget);
    });

    testWidgets('a non-dialable phone shows a warning rather than a dead tap', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const ShopDetailsScreen(shopId: 's1'),
          profile: _profile(phone: 'not-a-number'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('not-a-number'));
      await tester.pump();

      expect(find.text('This phone number cannot be dialed.'), findsOneWidget);
    });
  });

  group('coordinate-gated directions', () {
    testWidgets('shows Directions when coordinates are usable', (tester) async {
      await tester.pumpWidget(
        _app(
          const ShopDetailsScreen(shopId: 's1'),
          profile: _profile(latitude: 28.7150, longitude: 77.1150),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Directions'), findsOneWidget);
      expect(
        find.textContaining('Shop coordinates are temporarily unavailable'),
        findsNothing,
      );
    });

    testWidgets('hides Directions when coordinates are zero', (tester) async {
      await tester.pumpWidget(
        _app(
          const ShopDetailsScreen(shopId: 's1'),
          profile: _profile(latitude: 0, longitude: 0),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Directions'), findsNothing);
      expect(
        find.textContaining('Shop coordinates are temporarily unavailable'),
        findsOneWidget,
      );
    });

    testWidgets('hides Directions for out-of-range coordinates', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const ShopDetailsScreen(shopId: 's1'),
          profile: _profile(latitude: 999, longitude: 999),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Directions'), findsNothing);
      expect(
        find.textContaining('Shop coordinates are temporarily unavailable'),
        findsOneWidget,
      );
    });
  });

  group('inventory and offers', () {
    testWidgets('shows an empty state when the shop lists no products', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const ShopDetailsScreen(shopId: 's1'), profile: _profile()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Available Products'), findsOneWidget);
      expect(find.text('No products available'), findsOneWidget);
    });

    testWidgets('renders listed products with price and stock state', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const ShopDetailsScreen(shopId: 's1'),
          profile: _profile(
            products: const [
              ShopProductSummary(
                productId: 'p1',
                name: 'Blue Widget',
                imageUrl: 'https://example.com/p1.jpg',
                price: 499.0,
                isAvailable: true,
              ),
              ShopProductSummary(
                productId: 'p2',
                name: 'Red Widget',
                imageUrl: 'https://example.com/p2.jpg',
                price: 299.0,
                isAvailable: false,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The inventory grid is shrink-wrapped inside the page scroll view, so
      // every product is laid out and no extra scrolling is required.
      expect(find.text('Blue Widget'), findsOneWidget);
      expect(find.text('₹499'), findsOneWidget);
      expect(find.text('In Stock'), findsOneWidget);
      expect(find.text('Red Widget'), findsOneWidget);
      expect(find.text('₹299'), findsOneWidget);
      expect(find.text('Out of Stock'), findsOneWidget);
    });
  });

  // Master Spec §86-§89: the profile renders what the business actually offers.
  group('capability-driven surfaces', () {
    testWidgets('a restaurant shows its menu and no product grid', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const ShopDetailsScreen(shopId: 's1'),
          profile: _profile(capabilities: const ['menu', 'contact', 'ratings']),
          restaurant: const RestaurantProfile(
            id: 'r1',
            shopId: 's1',
            name: 'Annapurna Restaurant',
            menu: [
              RestaurantMenuSection(
                id: 'mc1',
                name: 'Main Course',
                items: [
                  RestaurantMenuItem(
                    id: 'mi1',
                    name: 'Paneer Butter Masala',
                    price: 240,
                    veg: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Menu'), findsOneWidget);
      expect(find.text('Main Course'), findsOneWidget);
      expect(find.text('Paneer Butter Masala'), findsOneWidget);
      expect(find.text('₹240'), findsOneWidget);

      // The product surface is absent, not empty: a restaurant is not a shop
      // with an out-of-stock catalogue.
      expect(find.text('Available Products'), findsNothing);
      expect(find.text('No products available'), findsNothing);
      expect(find.text('In Stock'), findsNothing);
      // Rule 4: nothing here can become an order.
      expect(find.textContaining('Add to cart'), findsNothing);
      expect(find.textContaining('Checkout'), findsNothing);
    });

    testWidgets('a restaurant with no published menu says so', (tester) async {
      await tester.pumpWidget(
        _app(
          const ShopDetailsScreen(shopId: 's1'),
          profile: _profile(capabilities: const ['menu', 'contact']),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Menu'), findsOneWidget);
      expect(find.textContaining('has not published a menu'), findsOneWidget);
      expect(find.text('Available Products'), findsNothing);
    });

    testWidgets('a transport provider shows services, not a price/stock grid', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const ShopDetailsScreen(shopId: 's1'),
          profile: _profile(
            capabilities: const ['service_profile', 'quote_request', 'contact'],
          ),
          service: const TransportServiceProfile(
            id: '9001',
            companyName: 'Raftaar City Movers',
            services: [
              TransportServiceOffering(
                id: 's1',
                serviceType: 'AIRPORT',
                name: 'Airport drops',
                basePrice: 650,
                priceUnit: 'PER_TRIP',
              ),
            ],
            vehicles: [
              ProviderVehicle(
                id: 'v1',
                vehicleType: 'SUV',
                make: 'Toyota',
                model: 'Innova',
                capacityPassengers: 6,
                acAvailable: true,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Services'), findsOneWidget);
      expect(find.text('Airport drops'), findsOneWidget);
      // A reference figure per unit, never a bare price with stock semantics.
      expect(find.text('₹650 / trip'), findsOneWidget);
      expect(find.text('Fleet (1)'), findsOneWidget);
      expect(find.textContaining('6 seats'), findsOneWidget);

      expect(find.text('Available Products'), findsNothing);
      expect(find.text('Out of Stock'), findsNothing);
      // The contract exists for a provider, so the entry point does.
      expect(find.text('Request a quote'), findsOneWidget);
    });

    testWidgets(
      'a provider without quote_request shows no booking entry point',
      (tester) async {
        await tester.pumpWidget(
          _app(
            const ShopDetailsScreen(shopId: 's1'),
            profile: _profile(
              capabilities: const ['service_profile', 'contact'],
            ),
            service: const TransportServiceProfile(
              id: '9001',
              companyName: 'Neighbourhood Workshop',
              services: [
                TransportServiceOffering(
                  id: 's1',
                  serviceType: 'OTHER',
                  name: 'Repairs',
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Services'), findsOneWidget);
        expect(find.text('Repairs'), findsOneWidget);
        // A booking form with no contract behind it would be a faked booking.
        expect(find.text('Request a quote'), findsNothing);
      },
    );

    testWidgets('a quoted service is labelled as quoted, not priced', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const ShopDetailsScreen(shopId: 's1'),
          profile: _profile(capabilities: const ['service_profile']),
          service: const TransportServiceProfile(
            id: '9001',
            companyName: 'Ola Hub',
            services: [
              TransportServiceOffering(
                id: 's1',
                serviceType: 'FAMILY_TOUR',
                name: 'Family tour',
                basePrice: 0,
                priceUnit: 'QUOTE',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('On quote'), findsOneWidget);
    });
  });
}
