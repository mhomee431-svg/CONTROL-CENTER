import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/token_store.dart';
import '../../../auth/domain/auth_models.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../data/shop_repository.dart';
import '../../domain/shop_models.dart';

enum ShopsStatus { initial, loading, ready, error }

class ShopsState {
  const ShopsState({
    required this.status,
    this.shops = const [],
    this.errorMessage,
    this.fieldErrors,
  });

  final ShopsStatus status;
  final List<ShopSummary> shops;
  final String? errorMessage;

  /// Server-side validation details (e.g. address problems).
  final Map<String, dynamic>? fieldErrors;

  factory ShopsState.initial() => const ShopsState(status: ShopsStatus.initial);
  factory ShopsState.loading({List<ShopSummary> shops = const []}) =>
      ShopsState(status: ShopsStatus.loading, shops: shops);
}

final shopsControllerProvider =
    NotifierProvider<ShopsController, ShopsState>(ShopsController.new);

class ShopsController extends Notifier<ShopsState> {
  @override
  ShopsState build() => ShopsState.initial();

  ShopRepository get _repo => ref.read(shopRepositoryProvider);

  Future<String?> _token() async {
    final tokens = ref.read(tokenStoreProvider);
    return tokens.readAccessToken();
  }

  Future<void> load() async {
    state = ShopsState.loading(shops: state.shops);
    try {
      final token = await _token();
      if (token == null) {
        state = const ShopsState(
            status: ShopsStatus.error, errorMessage: 'Not signed in');
        return;
      }
      final shops = await _repo.listMyShops(token);
      state = ShopsState(status: ShopsStatus.ready, shops: shops);
      // Keep the selection valid: drop it if the shop is no longer
      // authorized; auto-select when exactly one shop remains.
      final selected = ref.read(selectedShopProvider);
      final selectedId = selected?.id;
      if (selectedId != null && !shops.any((s) => s.id == selectedId)) {
        ref.read(selectedShopProvider.notifier).select(null);
      }
      if (selectedId == null && shops.length == 1) {
        ref.read(selectedShopProvider.notifier).select(shops.first);
      }
    } on ApiException catch (e) {
      state = ShopsState(status: ShopsStatus.error, errorMessage: e.message);
    } catch (_) {
      state = const ShopsState(
          status: ShopsStatus.error,
          errorMessage: 'Could not load your shops.');
    }
  }

  /// Registers a new shop owned by the current user and selects it.
  Future<bool> registerShop(Map<String, dynamic> payload) async {
    state = ShopsState.loading(shops: state.shops);
    try {
      final token = await _token();
      if (token == null) throw const ApiException(message: 'Not signed in');
      final detail = await _repo.registerShop(payload, token);
      await load(); // refresh the authorized list from source of truth
      final created = state.shops.where((s) => s.id == detail.summary.id);
      if (created.isNotEmpty) {
        ref.read(selectedShopProvider.notifier).select(created.first);
      }
      return true;
    } on ApiException catch (e) {
      state = ShopsState(
        status: ShopsStatus.error,
        shops: state.shops,
        errorMessage: e.message,
        fieldErrors: e.errorCode == 'VALIDATION_ERROR' ? const {} : null,
      );
      return false;
    } catch (_) {
      state = ShopsState(
        status: ShopsStatus.error,
        shops: state.shops,
        errorMessage: 'Shop registration failed. Please retry.',
      );
      return false;
    }
  }

  void clearError() {
    if (state.status == ShopsStatus.error) {
      state = ShopsState(status: ShopsStatus.ready, shops: state.shops);
    }
  }
}
