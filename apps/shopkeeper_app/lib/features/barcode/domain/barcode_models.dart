/// Domain models for the barcode scanner feature (Phase 24).
///
/// These map to the backend's `barcode_intake_service.resolve_barcode`
/// response shape, which differs from the shared `ShopProductItem`:
///   - `status` distinguishes FOUND / MULTIPLE_MATCHES / NOT_FOUND / INVALID
///   - `matches` carries catalog-level ProductMaster projections (not the
///     shop's own ShopProduct rows), each with selectable variants.
library;

/// A single catalog product match returned by `GET /barcodes/{barcode}/resolve`.
class CatalogProductMatch {
  const CatalogProductMatch({
    required this.productMasterId,
    required this.name,
    this.brandId,
    this.brand,
    this.imageUrl,
    this.status,
    required this.isAvailableInCatalog,
    required this.matchType,
    this.variants = const [],
  });

  final int productMasterId;
  final String name;
  final int? brandId;

  /// Human-readable brand name (may be null when the master has no brand).
  final String? brand;

  /// Primary product image URL (may be null when no image is attached).
  final String? imageUrl;

  final String? status;
  final bool isAvailableInCatalog;
  final String matchType;
  final List<ProductVariant> variants;

  factory CatalogProductMatch.fromJson(Map<String, dynamic> json) =>
      CatalogProductMatch(
        productMasterId: (json['product_master_id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? 'Unnamed',
        brandId: (json['brand_id'] as num?)?.toInt(),
        brand: json['brand_name'] as String?,
        imageUrl: json['image_url'] as String?,
        status: json['status'] as String?,
        isAvailableInCatalog:
            json['is_available_in_catalog'] as bool? ?? false,
        matchType: json['match_type'] as String? ?? 'IDENTIFIER',
        variants: ((json['variants'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ProductVariant.fromJson)
            .toList(growable: false),
      );
}

/// A SKU-level variant of a catalog master product.
class ProductVariant {
  const ProductVariant({
    required this.id,
    required this.name,
    this.sku,
  });

  final int id;
  final String name;
  final String? sku;

  factory ProductVariant.fromJson(Map<String, dynamic> json) => ProductVariant(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        sku: json['sku'] as String?,
      );
}

/// The full resolution payload from the backend.
///
/// `status` is one of: FOUND, MULTIPLE_MATCHES, NOT_FOUND, INVALID.
/// The API returns 300 for MULTIPLE_MATCHES and 404 for NOT_FOUND — those
/// are surfaced as [BarcodeResolutionStatus] values via the controller.
class BarcodeResolution {
  const BarcodeResolution({
    required this.status,
    required this.barcode,
    this.barcodeType,
    this.errorCode,
    this.message,
    this.matches = const [],
  });

  final BarcodeResolutionStatus status;
  final String barcode;
  final String? barcodeType;
  final String? errorCode;
  final String? message;
  final List<CatalogProductMatch> matches;

  factory BarcodeResolution.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status'] as String? ?? 'NOT_FOUND';
    return BarcodeResolution(
      status: BarcodeResolutionStatus.fromBackend(rawStatus),
      barcode: json['barcode'] as String? ?? '',
      barcodeType: json['barcode_type'] as String?,
      errorCode: json['error_code'] as String?,
      message: json['message'] as String?,
      matches: ((json['matches'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CatalogProductMatch.fromJson)
          .toList(growable: false),
    );
  }
}

/// Lifecycle states for a barcode resolution attempt.
enum BarcodeResolutionStatus {
  found,
  multipleMatches,
  notFound,
  invalid,
  networkError,
  serviceUnavailable;

  /// The backend uses uppercase strings in the JSON `status` field.
  /// HTTP-level errors (404, 503) and validation failures (INVALID) are
  /// mapped into these enum values by the repository.
  static BarcodeResolutionStatus fromBackend(String raw) => switch (raw) {
        'FOUND' => found,
        'MULTIPLE_MATCHES' => multipleMatches,
        'NOT_FOUND' => notFound,
        'INVALID' => invalid,
        _ => notFound,
      };
}
