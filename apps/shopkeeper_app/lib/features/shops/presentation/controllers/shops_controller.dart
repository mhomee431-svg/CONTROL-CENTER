import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/token_store.dart';
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
      // NOTE: selection validity / auto-select policy is NOT duplicated here.
      // AuthController listens to this `ready` state and runs the ONE
      // selection policy (drop invalid selection, auto-select when exactly
      // one shop) while mirroring the list into [AuthState.shops] for the
      // router guards — single source of truth for both.
    } on ApiException catch (e) {
      state = ShopsState(status: ShopsStatus.error, errorMessage: e.message);
    } catch (_) {
      state = const ShopsState(
          status: ShopsStatus.error,
          errorMessage: 'Could not load your shops.');
    }
  }

  bool _refreshInFlight = false;

  /// Silent re-fetch used by background resume/reconnect refreshes (see
  /// `features/shell/app_lifecycle_controller.dart`): keeps the current
  /// (possibly `ready`) state visible the whole time and only replaces it on
  /// success — the Shops screen must never flash a spinner for a background
  /// refresh it did not ask for. Re-entrant calls are dropped, never queued.
  Future<void> refresh() async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    try {
      final token = await _token();
      if (token == null) return; // signed out mid-flight → keep current state
      final shops = await _repo.listMyShops(token);
      state = ShopsState(status: ShopsStatus.ready, shops: shops);
    } catch (_) {
      // Silent: the auth listener only mirrors a `ready` list that actually
      // differs, so a failure leaves both this state and the session
      // snapshot untouched — the next resume/reconnect tries again.
    } finally {
      _refreshInFlight = false;
    }
  }

  /// Registers a new shop owned by the current user and returns the created
  /// detail, or `null` on failure (with [ShopsState.errorMessage] populated
  /// from the backend's own message).
  ///
  /// On success the authorized-shops list is refreshed from the backend and
  /// the created shop is selected, so every consumer of
  /// [selectedShopProvider] sees the new business without a second fetch.
  Future<ShopDetail?> registerShop(Map<String, dynamic> payload) async {
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
      return detail;
    } on ApiException catch (e) {
      state = ShopsState(
        status: ShopsStatus.error,
        shops: state.shops,
        errorMessage: e.message,
        fieldErrors: e.errorCode == 'VALIDATION_ERROR' ? const {} : null,
      );
      return null;
    } catch (_) {
      state = ShopsState(
        status: ShopsStatus.error,
        shops: state.shops,
        errorMessage: 'Shop registration failed. Please retry.',
      );
      return null;
    }
  }

  void clearError() {
    if (state.status == ShopsStatus.error) {
      state = ShopsState(status: ShopsStatus.ready, shops: state.shops);
    }
  }

  /// Clears ALL cached shop data (called on logout) so the previous
  /// account's business list never survives into the next session.
  void reset() => state = ShopsState.initial();
}
