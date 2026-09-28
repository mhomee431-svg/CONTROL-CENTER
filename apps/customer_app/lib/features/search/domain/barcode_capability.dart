import '../../../core/network/api_error_handler.dart';

/// Whether the backend actually serves `GET /search/v2/barcodes/{barcode}`.
///
/// WHY THIS EXISTS: barcode search has two independent failures that need
/// opposite reactions. "This barcode matches nothing" is real data — show an
/// empty state and let the customer scan again. "This deployment has no barcode
/// route" is not data, it is a missing feature; repeatedly showing an error for
/// a call that can never succeed is worse than not offering the entry point, so
/// the search screen removes the scan action once it learns this.
enum BarcodeSupport {
  /// Nothing has been attempted (or the last attempt was inconclusive) — keep
  /// the entry point visible and optimistic.
  unknown,

  /// At least one lookup answered successfully.
  supported,

  /// The backend rejected the route itself. Only this hides the entry point.
  unsupported;

  bool get isHidden => this == unsupported;
}

/// Copy shown when the server has no barcode route. Named "yet" because that is
/// what it is: a not-yet-deployed endpoint, not a broken customer action.
const String kBarcodeUnsupportedMessage =
    "Barcode search isn't available on this server yet. You can still search "
    'by product name.';

/// True when [error] means "the barcode route does not exist here".
///
/// Deliberately narrow. A 404 on a barcode is ambiguous — most shops answer it
/// for barcodes they simply do not stock — but a 404 on an unwired route is by
/// far the likelier cause here, so it counts. 405 (method not allowed) and 501
/// (not implemented) are unambiguous. Timeouts, offline, 401 and 5xx are NOT
/// capability signals: the route may exist and be fine, so the entry point must
/// survive them.
bool isMissingBarcodeRoute(Object? error) {
  if (error is! ApiException) return false;
  if (error.type == ApiErrorType.notFound) return true;
  return error.statusCode == 405 || error.statusCode == 501;
}
