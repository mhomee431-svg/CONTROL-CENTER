import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/home_repository.dart';
import '../../domain/models/home_data.dart';

final homeControllerProvider = FutureProvider.autoDispose<HomeData>((ref) async {
  final repo = ref.watch(homeRepositoryProvider);
  return await repo.fetchHomeFeed();
});