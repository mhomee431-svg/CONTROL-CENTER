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
}