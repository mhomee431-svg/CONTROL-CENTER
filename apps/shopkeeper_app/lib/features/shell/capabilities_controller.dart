import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_endpoints.dart';
import '../../core/network/api_providers.dart';
import '../../core/network/token_store.dart';
import '../auth/presentation/controllers/selected_shop.dart';
import '../shops/domain/shop_models.dart';

/// Single centralized capability/entitlement layer (spec §103–§104).
///
/// The backend derives the four `canX` flags ONLY from resolved subscription
/// entitlements (`derive_shop_capabilities`); this controller only READS them
/// to conditionally show functionality. No screen duplicates plan rules.
/// Backend remains authoritative (403 -> `ApiException.isEntitlementDenied`).
class CapabilitiesController extends Notifier<ShopCapabilities> {
  @override
  ShopCapabilities build() => const ShopCapabilities();

  /// Refresh from the lightweight capabilities endpoint
  /// (`GET /shopkeeper/shops/{id}/capabilities`). Fail-soft: a failure keeps
  /// the previous/permissive flags so a transient error never locks the
  /// shopkeeper out of their own screens.
  Future<void> load(int shopId, String token) async {
    try {
      final data = await ref.read(apiClientProvider).get(
            ApiEndpoints.shopCapabilities('$shopId'),
            token: token,
          ) as Map<String, dynamic>;
      state = ShopCapabilities.fromJson(data);
    } catch (_) {
      // Keep the current (permissive-by-default) flags.
    }
  }

  /// Same refresh, resolved from app state (the selected shop + the stored
  /// token) so callers never thread a token through for a background read.
  ///
  /// A no-op when no shop is selected — there is nothing to be entitled to,
  /// and guessing would leak one shop's flags onto another.
  Future<void> loadForSelectedShop() async {
    final shop = ref.read(selectedShopProvider);
    if (shop == null) return;
    final token = await ref.read(tokenStoreProvider).readAccessToken();
    if (token == null) return; // signed out mid-flight
    await load(shop.id, token);
  }

  /// Adopt flags already embedded in a dashboard / shop-detail payload
  /// (no extra round-trip).
  void adopt(ShopCapabilities capabilities) => state = capabilities;

  /// Clears cached flags (logout) so another account's entitlements never
  /// survive into the next session.
  void reset() => state = const ShopCapabilities();
}

/// The ONE source every screen gates off.
final capabilitiesControllerProvider =
    NotifierProvider<CapabilitiesController, ShopCapabilities>(
        CapabilitiesController.new);
