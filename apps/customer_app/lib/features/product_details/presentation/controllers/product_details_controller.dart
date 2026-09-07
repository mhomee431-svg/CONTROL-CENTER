import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/product_details_repository.dart';

part 'product_details_controller.g.dart';

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