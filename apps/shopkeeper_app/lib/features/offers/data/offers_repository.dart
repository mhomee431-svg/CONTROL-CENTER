import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_providers.dart';
import '../domain/offer_models.dart';

/// Offers contract for one authorized shop.
abstract class OffersRepository {
  /// Create + link an offer to the selected shop products (atomic on the
  /// backend). Throws [ApiException] on validation/permission failures.
  Future<OfferAssignResult> assignOffer(
    int shopId,
    OfferAssignRequest request,
    String token,
  );

  /// Offers belonging to this shop, newest window first.
  ///
  /// [status] filters by the shopkeeper-facing bucket (`active`, `scheduled`,
  /// `expired`, `draft`); omit it for every offer.
  Future<OfferListPage> fetchOffers(int shopId, String token, {String? status});
}

class ApiOffersRepository implements OffersRepository {
  ApiOffersRepository(this._api);

  final ApiClient _api;

  @override
  Future<OfferAssignResult> assignOffer(
    int shopId,
    OfferAssignRequest request,
    String token,
  ) async {
    final data = await _api.post(
      ApiEndpoints.assignOffer(shopId),
      body: request.toJson(),
      token: token,
    ) as Map<String, dynamic>;
    return OfferAssignResult.fromJson(data);
  }

  @override
  Future<OfferListPage> fetchOffers(
    int shopId,
    String token, {
    String? status,
  }) async {
    final data = await _api.get(
      ApiEndpoints.offers(shopId),
      token: token,
      query: {
        if (status != null && status.isNotEmpty) 'status': status,
      },
    ) as Map<String, dynamic>;
    return OfferListPage.fromJson(data);
  }
}

final offersRepositoryProvider = Provider<OffersRepository>((ref) {
  return ApiOffersRepository(ref.watch(apiClientProvider));
});
