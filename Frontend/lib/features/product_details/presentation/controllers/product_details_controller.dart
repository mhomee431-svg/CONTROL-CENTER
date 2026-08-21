import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/product_details_repository.dart';
import '../../domain/models/product_details_models.dart';

part 'product_details_controller.g.dart';

final productDetailsProvider = FutureProvider.autoDispose.family<ProductDetails, String>((ref, productId) async {
  final repo = ref.watch(productDetailsRepositoryProvider);
  return await repo.getProductDetails(productId);
});

@riverpod
class ProductActionController extends _$ProductActionController {
  @override
  void build() {
    // nothing to do
  }

  Future<void> toggleSave(String productId, bool currentStatus) async {
    final repo = ref.read(productDetailsRepositoryProvider);
    await repo.toggleSaveProduct(productId, !currentStatus);
  }
}
