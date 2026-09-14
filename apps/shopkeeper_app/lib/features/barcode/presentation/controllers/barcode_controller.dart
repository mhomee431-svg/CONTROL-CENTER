import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/token_store.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../../products/domain/product_models.dart';
import '../../data/barcode_repository.dart';
import '../../domain/barcode_models.dart';

/// State machine for the barcode-scanner flow (Phase 24).
///
/// States:
///   idle       — no scan has been attempted yet
///   resolving  — API call in-flight
///   resolved   — [resolution] is populated with matches (or empty → NOT_FOUND)
///   error      — [message] explains what went wrong
///   saving     — confirm-and-save API call in-flight
enum BarcodeScanStatus { idle, resolving, resolved, error, saving }

class BarcodeScanState {
  const BarcodeScanState({
    required this.status,
    this.scannedBarcode,
    this.resolution,
    this.message,
  });

  final BarcodeScanStatus status;
  final String? scannedBarcode;
  final BarcodeResolution? resolution;
  final String? message;

  factory BarcodeScanState.idle() =>
      const BarcodeScanState(status: BarcodeScanStatus.idle);

  BarcodeScanState resolvingWith(String barcode) => BarcodeScanState(
        status: BarcodeScanStatus.resolving,
        scannedBarcode: barcode,
      );

  BarcodeScanState resolvedWith(BarcodeResolution resolution) => BarcodeScanState(
        status: BarcodeScanStatus.resolved,
        scannedBarcode: resolution.barcode,
        resolution: resolution,
      );

  BarcodeScanState errorWith(String message, {String? barcode}) => BarcodeScanState(
        status: BarcodeScanStatus.error,
        scannedBarcode: barcode,
        message: message,
      );

  BarcodeScanState saving() => BarcodeScanState(
        status: BarcodeScanStatus.saving,
        scannedBarcode: scannedBarcode,
        resolution: resolution,
      );
}

/// Controller for the barcode-scanner flow (Phase 24).
class BarcodeController extends Notifier<BarcodeScanState> {
  @override
  BarcodeScanState build() => BarcodeScanState.idle();

  BarcodeRepository get _repo => ref.read(barcodeRepositoryProvider);
  TokenStore get _tokens => ref.read(tokenStoreProvider);
  int? get _shopId => ref.read(selectedShopProvider)?.id;

  /// Resolve a scanned barcode against the catalog.
  Future<void> resolve(String barcode) async {
    state = state.resolvingWith(barcode);
    try {
      final token = await _tokens.readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      final resolution = await _repo.resolveBarcode(barcode, _shopId, token);
      state = state.resolvedWith(resolution);
    } on ApiException catch (e) {
      // Only genuinely unexpected failures land here — the repository
      // converts NOT_FOUND / MULTIPLE_MATCHES / INVALID / 503 into proper
      // BarcodeResolution values (never throws for those outcomes).
      state = state.errorWith(_friendly(e), barcode: barcode);
    } catch (_) {
      state = BarcodeScanState(
        status: BarcodeScanStatus.error,
        scannedBarcode: barcode,
        message: 'Could not resolve barcode',
      );
    }
  }

  /// Technical exceptions → shopkeeper-friendly copy (same conventions as
  /// the shop-registration controller).
  String _friendly(ApiException e) {
    if (e.isUnauthorized || e.statusCode == 401) {
      return 'Your session has expired. Please sign in again.';
    }
    if (e.statusCode == 403) {
      return 'You do not have permission to scan for this shop.';
    }
    if (e.statusCode == null) {
      return 'No internet connection. Check your network and retry.';
    }
    return e.message;
  }

  /// Save a confirmed barcode scan to the shop's inventory.
  Future<ShopProductItem?> saveFromScan(BarcodeSavePayload payload) async {
    final shopId = _shopId;
    if (shopId == null) return null;
    state = state.saving();
    try {
      final token = await _tokens.readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      final created = await _repo.saveFromBarcode(shopId, payload, token);
      // Reset to idle after a successful save so the camera can scan again.
      state = BarcodeScanState.idle();
      return created;
    } on ApiException catch (e) {
      state = BarcodeScanState(
        status: BarcodeScanStatus.error,
        scannedBarcode: payload.barcode,
        message: e.message,
      );
      rethrow;
    } catch (_) {
      state = BarcodeScanState(
        status: BarcodeScanStatus.error,
        scannedBarcode: payload.barcode,
        message: 'Could not save product',
      );
      return null;
    }
  }

  /// Clear state and return to idle (e.g. after dismissing a result sheet).
  void reset() {
    state = BarcodeScanState.idle();
  }
}

final barcodeControllerProvider =
    NotifierProvider<BarcodeController, BarcodeScanState>(BarcodeController.new);
