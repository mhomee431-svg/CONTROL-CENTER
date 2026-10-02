/// Client-side barcode shape validation for the customer app.
///
/// WHY CLIENT-SIDE: the backend (`barcode_intake_service.validate_barcode_format`)
/// rejects malformed codes with `INVALID_BARCODE`, but sending a partial camera
/// read across the network just to learn it is 5 digits long wastes a request
/// and shows a generic failure for something the phone could have known
/// instantly. So the scan screen validates BEFORE the lookup and shows a
/// dedicated "that doesn't look right" notice instead of a lookup error; the
/// manual-entry sheet validates BEFORE submitting and shows an inline field
/// error instead of firing a request.
///
/// The rules mirror the backend exactly — normalize (strip spaces/dashes),
/// digits-only, GS1 lengths, GS1 check digit — except Code128, which the
/// backend's GS1 rules do not cover but the customer camera accepts (weighted
/// goods, inner packs). A Code128 read is validated as "plausible retail code":
/// alphanumeric, 4–48 chars. Anything stricter would reject real shelf labels.
library;

/// Why a barcode was rejected before any network call.
enum BarcodeInvalidReason {
  /// Nothing readable was captured (empty after normalization).
  empty,

  /// Contains characters no retail symbology uses.
  nonNumeric,

  /// Wrong length for every supported symbology.
  invalidLength,

  /// GS1 check digit does not verify — the classic partial/angled read.
  badCheckDigit,
}

/// Retail symbology lengths the customer flow accepts, mirroring
/// `MobileScannerController(formats: …)` on the scan screen and the backend's
/// `VALID_BARCODE_LENGTHS`.
const Set<int> kValidBarcodeLengths = {8, 12, 13, 14};

/// Human copy for an [BarcodeInvalidReason], shared by the scan notice and the
/// manual-entry field error so a bad code reads the same everywhere.
String invalidBarcodeMessage(BarcodeInvalidReason reason) {
  return switch (reason) {
    BarcodeInvalidReason.empty => 'No barcode was read. Hold the code steady inside the frame and try again.',
    BarcodeInvalidReason.nonNumeric =>
      'Only digits are valid in a product barcode. Re-scan, or type the digits '
          'printed under the bars.',
    BarcodeInvalidReason.invalidLength =>
      'Product barcodes are 8, 12, 13 or 14 digits. This looks like a partial '
          'read — hold still and scan again.',
    BarcodeInvalidReason.badCheckDigit =>
      'The last digit does not verify, so this is probably a misread. Scan '
          'again, or type the digits printed under the bars.',
  };
}

/// Strips the separators printed around barcodes on packaging, mirroring the
/// backend's `normalize_barcode`.
String normalizeBarcode(String? raw) =>
    (raw ?? '').trim().replaceAll(' ', '').replaceAll('-', '');

/// True when [raw] is shaped like a real product barcode.
///
/// Returns the rejection reason instead of a bool so the UI can explain WHAT
/// is wrong (actionable) rather than just THAT it is wrong. `null` means valid.
BarcodeInvalidReason? validateBarcode(String? raw) {
  final cleaned = normalizeBarcode(raw);
  if (cleaned.isEmpty) return BarcodeInvalidReason.empty;
  // Code128 (alphanumeric, variable length) is accepted by the camera but has
  // no GS1 check digit — accept plausible reads, reject obvious garbage.
  if (!RegExp(r'^[0-9]+$').hasMatch(cleaned)) {
    final code128Plausible =
        RegExp(r'^[A-Za-z0-9]+$').hasMatch(cleaned) && cleaned.length >= 4;
    if (!code128Plausible) return BarcodeInvalidReason.nonNumeric;
    return null;
  }
  if (!kValidBarcodeLengths.contains(cleaned.length)) {
    return BarcodeInvalidReason.invalidLength;
  }
  // GS1 check digit: rightmost data digit weighted 3, alternating 3/1 —
  // the same arithmetic as the backend's `validate_barcode_format`.
  final dataDigits = cleaned
      .substring(0, cleaned.length - 1)
      .split('')
      .reversed
      .map(int.parse)
      .toList();
  final expectedCheck = int.parse(cleaned[cleaned.length - 1]);
  var total = 0;
  for (var i = 0; i < dataDigits.length; i++) {
    total += (i.isEven ? 3 : 1) * dataDigits[i];
  }
  if ((10 - total % 10) % 10 != expectedCheck) {
    return BarcodeInvalidReason.badCheckDigit;
  }
  return null;
}
