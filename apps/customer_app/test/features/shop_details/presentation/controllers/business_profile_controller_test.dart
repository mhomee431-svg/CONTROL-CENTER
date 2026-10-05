import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/features/shop_details/domain/models/business_profile_models.dart';
import 'package:hyperlocal_app/features/shop_details/domain/models/shop_details_models.dart';
import 'package:hyperlocal_app/features/shop_details/domain/shop_details_repository.dart';
import 'package:hyperlocal_app/features/shop_details/presentation/controllers/business_profile_controller.dart';

/// Which business-side request the profile makes, per capability
/// (Master Spec §86-§89).
///
/// The point of these tests is the DECISION, not the rendering: a product shop
/// must cost one request, a restaurant must cost the menu request and never the
/// provider one, and a missing record must be a value rather than an error.
class _RecordingRepository implements ShopDetailsRepository {
  _RecordingRepository({this.restaurant, this.service, this.failure});

  final RestaurantProfile? restaurant;
  final TransportServiceProfile? service;
  final Object? failure;

  final List<String> calls = [];

  /// The capability list this fake's shop advertises.
  List<String> capabilities = const [];

  @override
  Future<ShopProfile> getShopProfile(String shopId) async {
    calls.add('shop:$shopId');
    return _shop(capabilities: capabilities);
  }

  @override
  Future<RestaurantProfile?> getRestaurantProfile(String shopId) async {
    calls.add('restaurant:$shopId');
    if (failure != null) throw failure!;
    return restaurant;
  }

  @override
  Future<TransportServiceProfile?> getTransportServiceProfile(
    String shopId,
  ) async {
    calls.add('service:$shopId');
    if (failure != null) throw failure!;
    return service;
  }

  @override
  Future<TransportQuoteReceipt> requestTransportQuote(
    TransportQuoteRequest request,
  ) async {
    calls.add('quote:${request.providerId}');
    return const TransportQuoteReceipt(quoteId: 'Q-1');
  }

  @override
  Future<void> toggleSaveShop(String shopId, bool save) async {}

  void serveCapabilities(List<String> capabilities) {
    this.capabilities = capabilities;
  }

  // Trips are account-scoped data this fake never needs, so it answers with an
  // empty list rather than an error.
  @override
  Future<TransportTrips> getMyTransportTrips() async => const TransportTrips();

  @override
  Future<TransportBooking> acceptTransportQuote(String quoteId) async =>
      throw StateError('this fake resolves profiles only');

  @override
  Future<TransportBooking> cancelTransportBooking(
    String bookingId, {
    String? reason,
  }) async => throw StateError('this fake resolves profiles only');
}

ShopProfile _shop({
  List<String> capabilities = const [],
  String businessType = '',
  List<String> categories = const [],
}) {
  return ShopProfile(
    id: 's1',
    name: 'Shop',
    imageUrl: '',
    rating: 4,
    reviewCount: 1,
    address: '',
    distanceInKm: 1,
    openingHours: '',
    isOpenNow: true,
    phone: '',
    about: '',
    lastInventoryUpdate: DateTime(2026),
    activeOffers: const [],
    availableProducts: const [],
    capabilities: capabilities,
    businessType: businessType,
    categories: categories,
  );
}

Future<BusinessProfile> _resolve(ShopDetailsRepository repository) async {
  final container = ProviderContainer(
    overrides: [shopDetailsRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  final provider = shopBusinessProfileProvider('s1');
  // Hold a listener for the duration of the read. The provider is autoDispose
  // (a shop profile section should not outlive the screen), so a bare
  // `read(future)` with no listener disposes it mid-flight and reports a
  // StateError instead of the real outcome — including a real failure.
  final subscription = container.listen(provider, (_, _) {});
  addTearDown(subscription.close);
  return await container.read(provider.future);
}

void main() {
  test(
    'a product shop costs one request and no business-profile call',
    () async {
      final repository = _RecordingRepository()
        ..serveCapabilities(const ['product_catalog', 'contact']);

      final profile = await _resolve(repository);

      expect(profile, isA<BusinessProfileNone>());
      // The identity request, and nothing else: a product shop must not pay for
      // a menu or a provider lookup.
      expect(repository.calls, ['shop:s1']);
    },
  );

  test('a restaurant fetches its menu and never the provider', () async {
    final repository = _RecordingRepository(
      restaurant: const RestaurantProfile(
        id: 'r1',
        shopId: 's1',
        name: 'Annapurna',
      ),
    )..serveCapabilities(const ['menu', 'contact']);

    final profile = await _resolve(repository);

    expect(profile, isA<BusinessProfileRestaurant>());
    expect((profile as BusinessProfileRestaurant).restaurant.id, 'r1');
    expect(repository.calls, ['shop:s1', 'restaurant:s1']);
  });

  test('a provider fetches its services and never the menu', () async {
    final repository = _RecordingRepository(
      service: const TransportServiceProfile(
        id: '9001',
        companyName: 'Raftaar',
      ),
    )..serveCapabilities(const ['service_profile', 'quote_request']);

    final profile = await _resolve(repository);

    expect(profile, isA<BusinessProfileService>());
    expect((profile as BusinessProfileService).service.id, '9001');
    expect(repository.calls, ['shop:s1', 'service:s1']);
  });

  test(
    'a capability with no published record is a value, not an error',
    () async {
      // A 404 from the by-shop lookup is a normal answer: the shop has the
      // capability but the record is not published yet.
      final repository = _RecordingRepository()
        ..serveCapabilities(const ['menu', 'contact']);

      final profile = await _resolve(repository);

      expect(profile, isA<BusinessProfileNone>());
      expect(repository.calls, ['shop:s1', 'restaurant:s1']);
    },
  );

  test('a failure surfaces as an error so the section can offer Retry', () async {
    final repository = _RecordingRepository(failure: Exception('network'))
      ..serveCapabilities(const ['service_profile']);

    // Asserted on the provider STATE rather than on its future: the provider is
    // autoDispose, so a failed load is exactly the case where a bare
    // `read(future)` can lose the real error to a disposal StateError. The state
    // is what a view actually renders from.
    final container = ProviderContainer(
      overrides: [shopDetailsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final provider = shopBusinessProfileProvider('s1');
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    // Drain the microtask queue until the load settles rather than awaiting
    // `.future`: with an autoDispose provider the future's error and the
    // listener's disposal race, and the state is what the view renders from.
    for (var i = 0; i < 20 && !container.read(provider).hasValue; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    final state = container.read(provider);
    // Riverpod RETRIES a failed future provider by default, so the settled state
    // is AsyncLoading(retrying) carrying the error rather than a terminal
    // AsyncError. Either way the section's Retry affordance is driven, and the
    // error the customer can be shown is the real one.
    expect(state.hasValue, isFalse, reason: 'no profile was produced');
    // The error is present and is the real one — not a disposal StateError that
    // would tell the customer to retry something that never failed.
    expect(state.error, isA<Exception>());
    expect(state.error, isNot(isA<StateError>()));
    // And the load is still in flight, which is what the section's Retry button
    // drives.
    expect(state.isLoading, isTrue);
  });
  test('a menu capability wins over a service one when both are present', () async {
    // Defensive: a payload should never grant both, but if it does the restaurant
    // surface is the one a customer can act on, and asking for both would make
    // two requests where one is needed.
    final repository = _RecordingRepository(
      restaurant: const RestaurantProfile(
        id: 'r1',
        shopId: 's1',
        name: 'Annapurna',
      ),
    )..serveCapabilities(const ['menu', 'service_profile']);

    final profile = await _resolve(repository);

    expect(profile, isA<BusinessProfileRestaurant>());
    expect(repository.calls, ['shop:s1', 'restaurant:s1']);
  });
}
