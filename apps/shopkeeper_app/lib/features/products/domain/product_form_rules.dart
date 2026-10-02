/// Which rule a product-form field broke.
///
/// Codes, never sentences: the wording belongs to `lib/l10n/app_en.arb` like
/// every other user-visible string in the app, so a translator reaches it and
/// the domain layer stays free of English. Resolve one through
/// [productFormErrorText] in the widget layer.
enum ProductFormFieldError {
  nameRequired('formProductNameRequired'),
  priceRequired('formSellingPriceRequired'),
  invalidAmount('formEnterValidAmount'),
  priceNegative('formPriceCannotBeNegative'),
  mrpNegative('formMrpCannotBeNegative'),
  mrpBelowPrice('formMrpBelowPrice'),
  wholeNumberRequired('formWholeNumberRequired'),
  quantityNegative('formQuantityCannotBeNegative'),

  /// Needs [ProductFormFieldFailure.count] — the minimum the value fell short of.
  barcodeTooShort('formBarcodeTooShort'),

  /// Needs [ProductFormFieldFailure.count] — the maximum the value exceeded.
  tooManyCharacters('formTooManyCharacters');

  const ProductFormFieldError(this.l10nKey);

  /// The `app_en.arb` key holding the shopkeeper-facing wording.
  final String l10nKey;
}

/// A broken rule, plus the numeric bound the value crossed when the wording
/// quotes it ("Use at most 120 characters").
class ProductFormFieldFailure {
  const ProductFormFieldFailure(this.code, {this.count});

  final ProductFormFieldError code;

  /// Only meaningful for [ProductFormFieldError.barcodeTooShort] and
  /// [ProductFormFieldError.tooManyCharacters].
  final int? count;

  @override
  bool operator ==(Object other) =>
      other is ProductFormFieldFailure &&
      other.code == code &&
      other.count == count;

  @override
  int get hashCode => Object.hash(code, count);

  @override
  String toString() =>
      'ProductFormFieldFailure(${code.name}${count == null ? '' : ', count: $count'})';
}

/// Client-side mirror of the backend's manual product-create contract.
///
/// The backend is the authority. `ShopkeeperProductCreate`
/// (backend/app/schemas/shopkeeper.py) requires exactly TWO fields — `name`
/// and `price` — and bounds every numeric field at `>= 0`. On top of the
/// schema, `shopkeeper_service` rejects `mrp < price`.
///
/// These rules mirror those constraints so the shopkeeper gets a fast,
/// friendly message instead of a 422 after a network round trip. They are
/// deliberately NOT stricter than the backend: no optional field is turned
/// into a required one, and no optional field gets a rule the backend does
/// not enforce. An "optional" rule below only fires once something is typed.
class ProductFormRules {
  ProductFormRules._();

  // ── Field maxima (mirror the backend schema) ────────────────────────────
  /// `name: str = Field(..., min_length=1, max_length=255)`
  static const int nameMaxLength = 255;

  /// `brand_name: str | None = Field(None, max_length=120)`
  static const int brandMaxLength = 120;

  /// `unit: str | None = Field(None, max_length=50)`
  static const int unitMaxLength = 50;

  /// `sku: str | None = Field(None, max_length=100)`
  static const int skuMaxLength = 100;

  /// `barcode: str | None = Field(None, min_length=4, max_length=100)`
  static const int barcodeMinLength = 4;
  static const int barcodeMaxLength = 100;

  /// Same normalisation the backend applies before checking the length, so a
  /// pasted " 123-45 " is judged by its real content, not its raw text.
  static String normalizeBarcode(String? raw) =>
      (raw ?? '').replaceAll(RegExp(r'[\s\-]'), '').trim();

  /// `barcode` is OPTIONAL. When present it must be 4–100 characters after
  /// the same strip the backend applies. Non-digits are allowed (they become
  /// a CUSTOM identifier) — no rule the backend does not enforce.
  static ProductFormFieldFailure? barcode(String? value) {
    final text = normalizeBarcode(value);
    if (text.isEmpty) return null; // optional
    if (text.length < barcodeMinLength) {
      return const ProductFormFieldFailure(
        ProductFormFieldError.barcodeTooShort,
        count: barcodeMinLength,
      );
    }
    if (text.length > barcodeMaxLength) {
      return const ProductFormFieldFailure(
        ProductFormFieldError.tooManyCharacters,
        count: barcodeMaxLength,
      );
    }
    return null;
  }

  /// Below this the backend's `ge=0` rejects the payload.
  static const double minimumAmount = 0;

  /// `name` is REQUIRED — the only mandatory text field.
  static ProductFormFieldFailure? name(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return const ProductFormFieldFailure(ProductFormFieldError.nameRequired);
    }
    if (text.length > nameMaxLength) {
      return const ProductFormFieldFailure(
        ProductFormFieldError.tooManyCharacters,
        count: nameMaxLength,
      );
    }
    return null;
  }

  /// `price` is REQUIRED and must be a number `>= 0`.
  static ProductFormFieldFailure? price(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return const ProductFormFieldFailure(ProductFormFieldError.priceRequired);
    }
    final parsed = double.tryParse(text);
    if (parsed == null) {
      return const ProductFormFieldFailure(ProductFormFieldError.invalidAmount);
    }
    if (parsed < minimumAmount) {
      return const ProductFormFieldFailure(ProductFormFieldError.priceNegative);
    }
    return null;
  }

  /// `mrp` is OPTIONAL. When present it must be `>= 0` and must not undercut
  /// the selling price (the backend raises "MRP cannot be lower than selling
  /// price"). [priceText] is the raw selling-price field at validation time.
  static ProductFormFieldFailure? mrp(
    String? value, {
    required String? priceText,
  }) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null; // optional — nothing typed, nothing to check
    final parsed = double.tryParse(text);
    if (parsed == null) {
      return const ProductFormFieldFailure(ProductFormFieldError.invalidAmount);
    }
    if (parsed < minimumAmount) {
      return const ProductFormFieldFailure(ProductFormFieldError.mrpNegative);
    }
    final price = double.tryParse((priceText ?? '').trim());
    if (price != null && parsed < price) {
      return const ProductFormFieldFailure(ProductFormFieldError.mrpBelowPrice);
    }
    return null;
  }

  /// `quantity` is OPTIONAL. When present it must be a whole number `>= 0`.
  static ProductFormFieldFailure? quantity(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null; // optional
    final parsed = int.tryParse(text);
    if (parsed == null) {
      return const ProductFormFieldFailure(
        ProductFormFieldError.wholeNumberRequired,
      );
    }
    if (parsed < 0) {
      return const ProductFormFieldFailure(
        ProductFormFieldError.quantityNegative,
      );
    }
    return null;
  }

  /// Any OPTIONAL free-text field with a backend maximum length.
  static ProductFormFieldFailure? optionalMax(String? value, int max) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null; // optional
    if (text.length > max) {
      return ProductFormFieldFailure(
        ProductFormFieldError.tooManyCharacters,
        count: max,
      );
    }
    return null;
  }
}
