import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/token_store.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../data/product_repository.dart';
import '../../domain/product_models.dart';

enum ProductsStatus { loading, ready, accessDenied, error }

class ProductsState {
  const ProductsState({
    required this.status,
    this.items = const [],
    this.summary,
    this.message,
  });

  final ProductsStatus status;
  final List<ShopProductItem> items;
  final InventorySummary? summary;
  final String? message;

  factory ProductsState.loading({ProductsState? from}) => ProductsState(
        status: ProductsStatus.loading,
        items: from?.items ?? const [],
        summary: from?.summary,
      );
}

final productsControllerProvider =
    NotifierProvider<ProductsController, ProductsState>(ProductsController.new);

class ProductsController extends Notifier<ProductsState> {
  @override
  ProductsState build() => ProductsState.loading();

  ProductRepository get _repo => ref.read(productRepositoryProvider);

  int? get _shopId => ref.read(selectedShopProvider)?.id;

  Future<void> load() async {
    final shopId = _shopId;
    if (shopId == null) {
      state = const ProductsState(
          status: ProductsStatus.error, message: 'No shop selected');
      return;
    }
    state = ProductsState.loading(from: state);
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      final overview = await _repo.fetchInventoryOverview(shopId, token);
      state = ProductsState(
        status: ProductsStatus.ready,
        items: overview.items,
        summary: overview.summary,
      );
    } on ApiException catch (e) {
      state = ProductsState(
        status: e.isForbidden ? ProductsStatus.accessDenied : ProductsStatus.error,
        message: e.message,
      );
    } catch (_) {
      state = const ProductsState(
          status: ProductsStatus.error,
          message: 'Could not load inventory.');
    }
  }

  Future<bool> setAvailability(int productId, bool available) async {
    final updated = await _patch(productId, {'is_available': available});
    return updated != null;
  }

  /// Clears a one-off error message after it has been surfaced.
  void clearTransientMessage() {
    if (state.message != null) {
      state = ProductsState(
        status: state.status,
        items: state.items,
        summary: state.summary,
      );
    }
  }

  Future<bool> saveEdits({
    required int productId,
    double? price,
    double? mrp,
    int? quantity,
    int? lowStockThreshold,
  }) async {
    final fields = <String, dynamic>{
      'price': ?price,
      'mrp': ?mrp,
      'quantity': ?quantity,
      'low_stock_threshold': ?lowStockThreshold,
    };
    return await _patch(productId, fields) != null;
  }

  /// Applies a PATCH and swaps the item in place with the server response.
  Future<ShopProductItem?> _patch(
      int productId, Map<String, dynamic> fields) async {
    final shopId = _shopId;
    if (shopId == null) return null;
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      final updated =
          await _repo.updateProduct(shopId, productId, fields, token);
      state = ProductsState(
        status: state.status == ProductsStatus.accessDenied
            ? ProductsStatus.accessDenied
            : ProductsStatus.ready,
        items: [
          for (final item in state.items)
            if (item.id == productId) updated else item,
        ],
        summary: state.summary,
      );
      return updated;
    } on ApiException catch (e) {
      state = ProductsState(
        status: e.isForbidden ? ProductsStatus.accessDenied : ProductsStatus.ready,
        items: state.items,
        summary: state.summary,
        message: e.message,
      );
      return null;
    } catch (_) {
      state = ProductsState(
        status: ProductsStatus.ready,
        items: state.items,
        summary: state.summary,
        message: 'Update failed. Please retry.',
      );
      return null;
    }
  }

  Future<bool> createProduct({
    required String name,
    required double price,
    double? mrp,
    String? unit,
    int quantity = 0,
    int lowStockThreshold = 5,
    required bool publish,
  }) async {
    final shopId = _shopId;
    if (shopId == null) return false;
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      final created = await _repo.createProduct(shopId, {
        'name': name,
        'price': price,
        'mrp': ?mrp,
        if (unit != null && unit.isNotEmpty) 'unit': unit,
        'quantity': quantity,
        'low_stock_threshold': lowStockThreshold,
        'publish': publish,
      }, token);
      state = ProductsState(
        status: ProductsStatus.ready,
        items: [created, ...state.items],
        summary: state.summary,
      );
      return true;
    } on ApiException catch (e) {
      state = ProductsState(
          status: ProductsStatus.ready,
          items: state.items,
          summary: state.summary,
          message: e.message);
      return false;
    } catch (_) {
      state = ProductsState(
          status: ProductsStatus.ready,
          items: state.items,
          summary: state.summary,
          message: 'Could not create the product.');
      return false;
    }
  }
}
