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
  Future<List<Shop>> fetchShopsByPincode(String pincode);
}
