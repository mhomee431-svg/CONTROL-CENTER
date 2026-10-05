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

  /// Which shop a read is currently answering for. Resume, reconnect and
  /// pull-to-refresh all fire this and can overlap; each overlap is an
  /// identical `GET .../capabilities` whose answer the app already has
  /// pending. Keying on the id (not a plain bool) means a read for a DIFFERENT
  /// shop still runs, because that one is genuinely new information.
  int? _inFlightShopId;

  /// Refresh from the lightweight capabilities endpoint
  /// (`GET /shopkeeper/shops/{id}/capabilities`). Fail-soft: a failure keeps
  /// the previous/permissive flags so a transient error never locks the
  /// shopkeeper out of their own screens.
  Future<void> load(int shopId, String token) async {
    if (_inFlightShopId == shopId) return; // already answering this question
    _inFlightShopId = shopId;
    try {
      final data = await ref.read(apiClientProvider).get(
            ApiEndpoints.shopCapabilities('$shopId'),
            token: token,
          ) as Map<String, dynamic>;
      // STALE-WRITE GUARD. Switching shops mid-flight is normal — the user
      // taps another shop while a refresh is running — and the two requests
      // can complete out of order. Writing unconditionally would let the
      // older shop's answer land last and gate the WRONG shop, which is the
      // exact entitlement mix-up this controller exists to prevent. Only the
      // most recent read may publish.
      if (_inFlightShopId == shopId) {
        state = ShopCapabilities.fromJson(data);
      }
    } catch (_) {
      // Keep the current (permissive-by-default) flags.
    } finally {
      if (_inFlightShopId == shopId) _inFlightShopId = null;
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
  void reset() {
    state = const ShopCapabilities();
    // Forget the in-flight read too. Otherwise a request that is still
    // resolving can publish the NEXT account's flags after logout, which is
    // the cross-session leak this method exists to prevent.
    _inFlightShopId = null;
  }
}

/// The ONE source every screen gates off.
final capabilitiesControllerProvider =
    NotifierProvider<CapabilitiesController, ShopCapabilities>(
        CapabilitiesController.new);
