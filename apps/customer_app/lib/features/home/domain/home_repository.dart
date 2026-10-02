import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/local_cache_service.dart';
import '../../../core/network/api_client.dart';
import '../data/api_home_repository.dart';
import 'models/home_data.dart';

final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  return ApiHomeRepository(
    ref.watch(apiClientProvider),
    ref.watch(localCacheServiceProvider),
  );
});

abstract class HomeRepository {
  /// Fetches the home feed. Coordinates are optional: when supplied, the
  /// backend ranks/sorts nearby content by distance.
  Future<HomeData> fetchHomeFeed({double? latitude, double? longitude});

  /// Fetches the shops that serve a manually entered 6-digit area pin code
  /// (`GET /shops/nearby?pincode=...`, public — no auth required).
  ///
  /// Ownership: nearby-shop discovery belongs to this repository, the same
  /// domain as the home feed's distance-ranked `nearby_shops` — the pin code
  /// is only another geolocation input for the same query. Screens never
  /// call the API directly.
  /// Fetches ONE PAGE of the shops that serve a manually entered 6-digit area
  /// pin code (`GET /shops/nearby?pincode=...&page=...&limit=...`, public).
  ///
  /// PAGINATION, and why it is not optional
  /// --------------------------------------
  /// This used to return every match, which meant one request could materialise
  /// an entire area's catalogue into a list. A dense pincode is unbounded, so
  /// that is not a safe default for any list endpoint.
  ///
  /// `page` is 1-based. Callers page until a page comes back short, which is
  /// the signal [ShopsByPinPage.hasMore] already carries.
  ///
  /// The endpoint speaks `page`/`limit` offset pagination, not a cursor.
  /// Offset paging gets slower server-side on deep pages, and rows can shift
  /// between requests if the catalogue changes mid-scroll, so an offset client
  /// can duplicate or skip a shop. A `(sort_key, id)` keyset would fix both and
  /// is a deliberate backend+client change; until then, offset is the contract.
  Future<ShopsByPinPage> fetchShopsByPincode(
    String pincode, {
    int page = 1,
    required int limit,
  });
}

/// One page of nearby shops for a pin code.
class ShopsByPinPage {
  const ShopsByPinPage({required this.shops, required this.hasMore});

  final List<Shop> shops;

  /// False when the backend returned fewer than `limit` rows, i.e. the end of
  /// the result set has been reached.
  final bool hasMore;

  static const empty = ShopsByPinPage(shops: [], hasMore: false);
}
