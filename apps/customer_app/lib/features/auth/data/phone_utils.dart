/// Indian phone-number utilities.
///
/// The app is India-only, so users should never have to type `+91` — a bare
/// 10-digit number is normalized to the E.164 form `+91XXXXXXXXXX` that
/// Firebase Phone Auth and the backend both expect.
library;

/// Normalize an Indian mobile number to E.164 (`+91…`).
///
/// Accepts all common formats:
///   - `9999999999`            -> `+919999999999`
///   - `09999999999`           -> `+919999999999`  (leading 0 dropped)
///   - `919999999999`          -> `+919999999999`  (91 prefix kept)
///   - `+919999999999`         -> unchanged
///   - `+91 99999 99999`       -> unchanged
///   - `99999-99999`           -> `+919999999999`
///
/// Returns the trimmed original when it cannot be recognised as an Indian
/// mobile number (caller/backend will then report the precise error).
String normalizeIndianPhone(String raw) {
  final input = raw.trim();
  var digits = input.replaceAll(RegExp(r'\D'), '');

  if (digits.length == 11 && digits.startsWith('0')) {
    digits = digits.substring(1); // drop leading trunk 0 → 10 digits
  }
  // Normalize country-code variants to the canonical 10 digits.
  if (digits.length == 12 && digits.startsWith('91')) {
    digits = digits.substring(2); // "9199…" → "99…"
  } else if (digits.length == 11 && digits.startsWith('91')) {
    digits = digits.substring(2); // duplicate "9191…" → "91…" (rare)
  }
  if (digits.length == 10) {
    return '+91$digits';
  }
  return input;
}
