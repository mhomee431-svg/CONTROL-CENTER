import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/network/api_error_handler.dart';
import 'package:hyperlocal_app/core/router/deep_link.dart';
import 'package:hyperlocal_app/core/router/deep_link_guard.dart';
import 'package:hyperlocal_app/core/router/deep_link_launcher.dart';
import 'package:hyperlocal_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_app/features/product_details/domain/models/product_details_models.dart';
import 'package:hyperlocal_app/features/product_details/domain/product_details_repository.dart';
import 'package:hyperlocal_app/features/shop_details/domain/models/shop_details_models.dart';
import 'package:hyperlocal_app/features/shop_details/domain/shop_details_repository.dart';
import 'package:hyperlocal_app/features/shop_details/domain/models/business_profile_models.dart';

/// Throws [error] from every read; null means the read succeeds.
class _FakeProductRepository implements ProductDetailsRepository {
  final Object? error;
  _FakeProductRepository({this.error});

  @override
  Future<ProductDetails> getProductDetails(
    String productId, {
    double? radiusKm,
  }) async {
    if (error != null) throw error!;
    return ProductDetails(
      product: ProductMasterDetails(
        id: productId,
        name: 'Dove Bar',
        brand: 'Dove',
        description: '',
        imageUrls: const [],
        category: 'Beauty',
        attributes: const [],
        variants: const [],
        identifiers: const [],
      ),
    );
  }

  @override
  Future<void> toggleSaveProduct(String productId, bool save) async {}
}

class _FakeShopRepository implements ShopDetailsRepository {
  final Object? error;
  _FakeShopRepository({this.error});

  @override
  Future<ShopProfile> getShopProfile(String shopId) async {
    if (error != null) throw error!;
    return ShopProfile(
      id: shopId,
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
    );
  }

  @override
  Future<void> toggleSaveShop(String shopId, bool save) async {}

  // Deep links resolve a shop IDENTITY, so this fake has no restaurant or
  // provider behind it — which is also the honest answer for a deep link into
  // a product shop.
  @override
  Future<RestaurantProfile?> getRestaurantProfile(String shopId) async => null;

  @override
  Future<TransportServiceProfile?> getTransportServiceProfile(
    String shopId,
  ) async => null;

  @override
  Future<TransportQuoteReceipt> requestTransportQuote(
    TransportQuoteRequest request,
  ) async => throw StateError('a deep link never requests a quote');

  // Trips are account-scoped data this probe never touches, so an empty list is
  // the honest answer rather than an error.
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

RepositoryDeepLinkProbe probeWith({Object? productError, Object? shopError}) {
  return RepositoryDeepLinkProbe(
    products: _FakeProductRepository(error: productError),
    shops: _FakeShopRepository(error: shopError),
  );
}

ApiException apiError(ApiErrorType type, {int? status}) =>
    ApiException(type: type, message: 'boom', statusCode: status);

const DeepLinkIntent productLink = DeepLinkIntent(
  entity: DeepLinkEntity.product,
  id: 'p1',
);
const DeepLinkIntent shopLink = DeepLinkIntent(
  entity: DeepLinkEntity.shop,
  id: 's1',
);

void main() {
  group('an authoritative 404 means the entity is gone', () {
    test('a deleted product is reported as gone', () async {
      // THE BUG THIS GUARDS: the probe used to swallow every exception and
      // report "available", so a shared link to a deleted product opened a
      // detail screen whose only option was a retry that could never succeed.
      final state = await probeWith(
        productError: apiError(ApiErrorType.notFound, status: 404),
      ).probe(productLink);

      expect(state, DeepLinkTargetState.gone);
    });

    test('a deleted shop is reported as gone', () async {
      final state = await probeWith(
        shopError: apiError(ApiErrorType.notFound, status: 404),
      ).probe(shopLink);

      expect(state, DeepLinkTargetState.gone);
    });

    test('the gone verdict reaches the customer as not-found copy', () async {
      // End to end through the guard: `gone` must not be a state the UI can
      // never actually render, which is what made this look handled already.
      final decision = await evaluateDeepLink(
        intent: productLink,
        environment: DeepLinkEnvironment(
          authStatus: AuthStatus.authenticated,
          isAppReady: true,
          now: DateTime(2026),
        ),
        probe: probeWith(
          productError: apiError(ApiErrorType.notFound, status: 404),
        ),
      );

      expect(decision.isAllowed, isFalse);
      expect(decision.reason, DeepLinkBlockReason.notFound);
      expect(decision.fallbackPath, isNotEmpty);
    });
  });

  group('every other failure stays fail-open', () {
    // Fail-open is deliberate: the detail screen already renders an
    // error-and-retry state, so refusing here would replace a recoverable screen
    // with a dead end for every customer on a flaky connection.
    for (final type in [
      ApiErrorType.offline,
      ApiErrorType.timeout,
      ApiErrorType.serverError,
      ApiErrorType.partialFailure,
    ]) {
      test('$type is available, not gone', () async {
        final state = await probeWith(productError: apiError(type))
            .probe(productLink);
        expect(state, DeepLinkTargetState.available);
      });
    }

    test('a 401 is NOT reported as gone', () async {
      // Telling a signed-out customer a product "no longer exists" would be a
      // lie: it exists, they simply cannot see it. The guard already refuses
      // these links earlier for being account-scoped.
      final state = await probeWith(
        productError: apiError(ApiErrorType.sessionExpired, status: 401),
      ).probe(productLink);

      expect(state, DeepLinkTargetState.available);
    });

    test('a 403 is NOT reported as gone', () async {
      final state = await probeWith(
        productError: apiError(ApiErrorType.accessDenied, status: 403),
      ).probe(productLink);

      expect(state, DeepLinkTargetState.available);
    });

    test('an unexpected non-API exception is still available', () async {
      final state = await probeWith(productError: StateError('unexpected'))
          .probe(productLink);

      expect(state, DeepLinkTargetState.available);
    });
  });

  group('entities that need no lookup are unaffected', () {
    test('a successful product read is available', () async {
      expect(
        await probeWith().probe(productLink),
        DeepLinkTargetState.available,
      );
    });

    test(
      'an offer is unavailable, because it has no backing screen yet',
      () async {
        final state = await probeWith().probe(
          const DeepLinkIntent(entity: DeepLinkEntity.offer, id: 'o1'),
        );
        expect(state, DeepLinkTargetState.unavailable);
      },
    );

    test(
      'search and notification links never touch the repositories',
      () async {
        // Both must be unaffected by the 404 handling: they are not entity
        // addressed, so a 404 raised on some other screen cannot refuse them.
        final probe = probeWith(
          productError: apiError(ApiErrorType.notFound, status: 404),
        );
        expect(
          await probe.probe(const DeepLinkIntent.search('milk')),
          DeepLinkTargetState.available,
        );
        expect(
          await probe.probe(const DeepLinkIntent.notifications()),
          DeepLinkTargetState.available,
        );
      },
    );
  });
}
