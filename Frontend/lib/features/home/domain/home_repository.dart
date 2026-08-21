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
  Future<HomeData> fetchHomeFeed();
}