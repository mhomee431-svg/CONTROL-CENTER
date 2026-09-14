import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_providers.dart';
import '../../products/domain/product_models.dart';
import '../domain/barcode_models.dart';

/// Barcode scan + inventory-intake contract for a single shop.
abstract class BarcodeRepository {
  /// Resolve a scanned barcode to catalog product matches.
  ///
  /// FOUND / MULTIPLE_MATCHES / NOT_FOUND / INVALID are all returned as
  /// [BarcodeResolution] values — never thrown — so callers can render each
  /// outcome without try/catch branching. Network / 5xx failures throw.
  Future<BarcodeResolution> resolveBarcode(
      String barcode, int? shopId, String token);

  /// Confirm the scanned product and persist it to the shop's inventory.
  ///
  /// Returns the newly-created [ShopProductItem] (same shape as the
  /// inventory PATCH/POST responses). Throws [ApiException] on failure
  /// (409 CONFLICT when the product is already in inventory).
  Future<ShopProductItem> saveFromBarcode(
      int shopId, BarcodeSavePayload payload, String token);
}

/// Payload for confirming a resolved barcode scan into a shop listing.
///
/// Mirrors the backend `BarcodeSaveRequest` schema (Phase 24).
class BarcodeSavePayload {
  const BarcodeSavePayload({
    required this.barcode,
    required this.productMasterId,
    this.variantId,
    required this.price,
    this.mrp,
    this.sku,
    this.quantity = 0,
    this.lowStockThreshold = 5,
    this.isAvailable = true,
    this.publish = true,
  });

  final String barcode;
  final int productMasterId;
  final int? variantId;
  final double price;
  final double? mrp;
  final String? sku;
  final int quantity;
  final int lowStockThreshold;
  final bool isAvailable;
  final bool publish;

  Map<String, dynamic> toJson() => {
        'barcode': barcode,
        'product_master_id': productMasterId,
        if (variantId != null) 'variant_id': variantId,
        'price': price,
        if (mrp != null) 'mrp': mrp,
        if (sku != null && sku!.isNotEmpty) 'sku': sku,
        'quantity': quantity,
        'low_stock_threshold': lowStockThreshold,
        'is_available': isAvailable,
        'publish': publish,
      };
}

class ApiBarcodeRepository implements BarcodeRepository {
  ApiBarcodeRepository(this._api);

  final ApiClient _api;

  @override
  Future<BarcodeResolution> resolveBarcode(
      String barcode, int? shopId, String token) async {
    try {
      final data = await _api.get(
        ApiEndpoints.barcodeResolve(barcode),
        token: token,
        query: shopId != null ? {'shop_id': shopId} : null,
      ) as Map<String, dynamic>;
      return BarcodeResolution.fromJson(data);
    } on ApiException catch (e) {
      // The backend signals NOT_FOUND (404), MULTIPLE_MATCHES (300) and
      // INVALID (400) as error envelopes — but all three are *valid*
      // resolution outcomes. The matches live inside the error `data` field.
      // Reconstruct a proper BarcodeResolution so callers treat every
      // outcome uniformly.
      final status = switch (e.statusCode) {
        300 => BarcodeResolutionStatus.multipleMatches,
        404 => BarcodeResolutionStatus.notFound,
        400 => BarcodeResolutionStatus.invalid,
        503 => BarcodeResolutionStatus.serviceUnavailable,
        _ => null,
      };
      if (status != null) {
        final data = e.data is Map<String, dynamic>
            ? e.data as Map<String, dynamic>
            : const <String, dynamic>{};
        return BarcodeResolution(
          status: status,
          barcode: data['barcode'] as String? ?? barcode,
          barcodeType: data['barcode_type'] as String?,
          errorCode: e.errorCode,
          message: e.message,
          matches: ((data['matches'] as List<dynamic>?) ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(CatalogProductMatch.fromJson)
              .toList(growable: false),
        );
      }
      // Session / shop-access / unknown errors — surface as real failures.
      rethrow;
    }
  }

  @override
  Future<ShopProductItem> saveFromBarcode(
      int shopId, BarcodeSavePayload payload, String token) async {
    final data = await _api.post(
      '${ApiEndpoints.products('$shopId')}/from-barcode',
      body: payload.toJson(),
      token: token,
    ) as Map<String, dynamic>;
    return ShopProductItem.fromJson(data);
  }
}

final barcodeRepositoryProvider = Provider<BarcodeRepository>((ref) {
  return ApiBarcodeRepository(ref.watch(apiClientProvider));
});
