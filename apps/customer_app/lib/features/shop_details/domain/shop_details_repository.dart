import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/local_cache_service.dart';
import '../../../core/network/api_client.dart';
import 'models/business_profile_models.dart';
import 'models/shop_details_models.dart';
import '../data/api_shop_details_repository.dart';

final shopDetailsRepositoryProvider = Provider<ShopDetailsRepository>((ref) {
  return ApiShopDetailsRepository(
    ref.watch(apiClientProvider),
    ref.watch(localCacheServiceProvider),
  );
});

abstract class ShopDetailsRepository {
  Future<ShopProfile> getShopProfile(String shopId);
  Future<void> toggleSaveShop(String shopId, bool save);

  /// The restaurant side of this shop, or null when it has no restaurant
  /// profile behind it.
  ///
  /// Called ONLY for a business whose capabilities include `menu`. A null
  /// answer is a normal outcome (no record published yet) — the caller shows
  /// no menu rather than an empty one, and never a cart or a checkout.
  Future<RestaurantProfile?> getRestaurantProfile(String shopId);

  /// The transport / travel side of this shop, or null when it has no provider
  /// record behind it.
  ///
  /// Called ONLY for a business whose capabilities include `service_profile`.
  /// Null means: show no service section, and in particular no request/booking
  /// entry point — a form with nothing behind it would be a faked booking.
  Future<TransportServiceProfile?> getTransportServiceProfile(String shopId);

  /// Asks a provider for a trip price (`POST /transport/quotes`).
  ///
  /// The price is quoted BACK by the provider; this call only acknowledges that
  /// the request landed. Implementations must let backend errors surface — the
  /// request ViewModel turns them into user-safe copy.
  Future<TransportQuoteReceipt> requestTransportQuote(
    TransportQuoteRequest request,
  );

  /// The customer's own quote requests, newest first.
  ///
  /// The list that carries the provider's price. Without it a requested quote is
  /// a dead end: the customer cannot read the answer, so they cannot accept it.
  Future<TransportTrips> getMyTransportTrips();

  /// Accepts a quoted price, creating the booking (`POST /transport/quotes/{id}/accept`).
  ///
  /// The agreed amount is the PROVIDER's quoted price, never one the app
  /// computes. Errors surface so the view can explain why (already accepted,
  /// not yet quoted, not yours).
  Future<TransportBooking> acceptTransportQuote(String quoteId);

  /// Cancels a booking the customer can no longer use
  /// (`POST /transport/bookings/{id}/cancel`).
  Future<TransportBooking> cancelTransportBooking(
    String bookingId, {
    String? reason,
  });
}
