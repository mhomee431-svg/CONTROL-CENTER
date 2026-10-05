/// The ONE place validation rules live.
///
/// Why this file exists: the app had three *different* phone rules at once —
/// `InputValidator` accepted `^[+?]?[0-9]{10,12}$`, `login_screen` enforced
/// `^[6-9]\d{9}$`, and `phone_utils` normalised Indian numbers. A user who
/// typed a number accepted by one screen was rejected by the next. Rules that
/// disagree are worse than no rules.
///
/// ## The India-only rule
/// This app is India-only (`phone_utils.dart` documents that and Firebase Phone
/// Auth is provisioned for +91). So a "valid phone number" means a valid
/// **Indian mobile**: 10 digits starting 6-9. Landline (STD) numbers, and
/// numbers starting 0/1/2/3/4/5, are rejected deliberately.
///
/// ## Two flavours, on purpose
/// Each field type has a `validate*` (returns a `String?` for
/// `TextFormField.validator`) and a bare `is*` predicate (for controllers and
/// submit guards). They share one regex so the two can never drift.
library;

import 'package:flutter/services.dart';

/// Shared sanitisation of user free-text before it is stored or logged.
abstract final class InputSanitizer {
  /// Control characters (including NUL and DEL) plus angle brackets.
  ///
  /// Angle brackets are stripped rather than escaped: no consumer of this input
  /// renders it as HTML, so escaping would leave visible `&lt;` in search
  /// history, and stripping is what actually removes an XSS vector.
  static final RegExp _unsafe = RegExp(r'[\x00-\x1F\x7F<>]');

  /// Collapses runs of whitespace, then trims.
  static String text(String input) =>
      input.replaceAll(_unsafe, '').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Same as [text] but preserves internal newlines, for multi-line fields
  /// such as an address. `trim()` only strips the outer whitespace.
  static String multiline(String input) => input
      .replaceAll(_unsafe, '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  /// Digits only, with a single optional leading `+`.
  static String phone(String input) => input.replaceAll(RegExp(r'[^\d+]'), '');

  /// Numeric only — no sign, no decimal point. For pincode and OTP.
  static String digits(String input) => input.replaceAll(RegExp(r'\D'), '');
}

/// Indian mobile numbers.
abstract final class PhoneValidator {
  /// 10 digits, first digit 6-9. See the class docs for why.
  static final RegExp _pattern = RegExp(r'^[6-9]\d{9}$');

  static final String requiredMessage = 'Phone number is required.';
  static final String formatMessage = 'Enter a valid 10-digit mobile number.';

  /// Digits only, no `+`/spaces, length 10, starts 6-9.
  ///
  /// Accepts the formats people actually paste or type, including `+91`:
  /// login renders `prefixText: '+91 '`, so `+91 98765 43210` is a normal
  /// thing to be holding. The country code and a leading trunk 0 are stripped
  /// BEFORE the 10-digit check — without that, a pasted `+919876543210` was
  /// rejected for having "12 digits".
  static bool isValid(String? value) {
    if (value == null) return false;
    return _pattern.hasMatch(_toLocalDigits(value));
  }

  /// The bare 10-digit Indian mobile number, with `+91` / `91` / leading `0`
  /// removed. Mirrors `normalizeIndianPhone` in `features/auth/domain`.
  static String _toLocalDigits(String value) {
    var d = InputSanitizer.digits(value);
    if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
    if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
    if (d.length == 11 && d.startsWith('91')) d = d.substring(2);
    return d;
  }

  /// `TextFormField.validator` flavour.
  static String? validate(String? value) {
    if (value == null || value.trim().isEmpty) return requiredMessage;
    return isValid(value) ? null : formatMessage;
  }
}

/// Email addresses.
abstract final class EmailValidator {
  /// TLD is `[A-Za-z]{2,63}` rather than a short fixed range. The previous rule
  /// in `InputValidator` used `{2,4}`, which silently rejected real addresses
  /// at `.museum`, `.travel` and `.photography`.
  static final RegExp _pattern = RegExp(
    r"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?"
    r'(?:\.[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?)*'
    r'\.[A-Za-z]{2,63}$',
  );

  static final String requiredMessage = 'Email address is required.';
  static final String formatMessage = 'Please enter a valid email address.';

  static bool isValid(String? value) {
    if (value == null) return false;
    final v = value.trim();
    // Length guard first: the regex on a 5000-char string is a needless
    // backtracking risk, and no real address is this long.
    if (v.isEmpty || v.length > 254) return false;
    return _pattern.hasMatch(v);
  }

  static String? validate(String? value) {
    if (value == null || value.trim().isEmpty) return requiredMessage;
    return isValid(value) ? null : formatMessage;
  }

  /// For genuinely OPTIONAL contact fields ("so we can follow up with you").
  ///
  /// Blank passes. A non-blank value must still be a real address — "leave it
  /// empty" is not an invitation to accept `abc@`.
  static String? validateOptional(String? value, {String? message}) {
    if (value == null || value.trim().isEmpty) return null;
    // `message` cannot default to `formatMessage` in the signature: a default
    // parameter value must be a compile-time constant, and that field is
    // `static final` precisely so callers can localise it at runtime.
    return isValid(value) ? null : (message ?? formatMessage);
  }
}

/// Free-text search queries.
abstract final class SearchValidator {
  static const int maxLength = 100;
  static final String tooLongMessage =
      'Search query is too long (max $maxLength characters).';

  /// Empty is VALID. A search box may legitimately be empty; whether that is
  /// an error is the submit button's business, not the field's.
  static bool isValid(String? value) {
    if (value == null) return true;
    return value.length <= maxLength;
  }

  static String? validate(String? value) =>
      isValid(value) ? null : tooLongMessage;

  /// Sanitised, length-capped query ready to send.
  static String sanitize(String? value) {
    final t = InputSanitizer.text(value ?? '');
    return t.length > maxLength ? t.substring(0, maxLength) : t;
  }
}

/// Indian PIN codes.
abstract final class PincodeValidator {
  /// 6 digits. No leading zero: PIN codes are 100000-999999.
  static final RegExp _pattern = RegExp(r'^[1-9]\d{5}$');

  static final String requiredMessage = 'PIN code is required.';
  static final String formatMessage = 'Enter a valid 6-digit PIN code.';

  static bool isValid(String? value) {
    if (value == null) return false;
    return _pattern.hasMatch(InputSanitizer.digits(value));
  }

  static String? validate(String? value) {
    if (value == null || value.trim().isEmpty) return requiredMessage;
    return isValid(value) ? null : formatMessage;
  }
}

/// Personal names.
abstract final class NameValidator {
  /// Unicode letters, plus space, hyphen, apostrophe and dot.
  ///
  /// Deliberately Unicode rather than `[A-Za-z]`: "José", "Müller" and "राहुल"
  /// are all legitimate names, and an ASCII-only rule would reject them.
  static final RegExp _pattern = RegExp(
    r"^[\p{L}\p{M}][\p{L}\p{M} .'\-]*$",
    unicode: true,
  );

  static const int minLength = 2;
  static const int maxLength = 50;

  static final String requiredMessage = 'Name is required.';
  static final String tooShortMessage =
      'Name must be at least $minLength characters.';
  static final String tooLongMessage =
      'Name must be at most $maxLength characters.';
  static final String formatMessage =
      'Use letters, spaces, hyphens and apostrophes only.';

  static bool isValid(String? value) {
    if (value == null) return false;
    final v = value.trim();
    if (v.length < minLength || v.length > maxLength) return false;
    return _pattern.hasMatch(v);
  }

  static String? validate(String? value) {
    final v = value?.trim();
    if (v == null || v.isEmpty) return requiredMessage;
    if (v.length < minLength) return tooShortMessage;
    if (v.length > maxLength) return tooLongMessage;
    return _pattern.hasMatch(v) ? null : formatMessage;
  }
}

/// Free-text postal addresses.
abstract final class AddressValidator {
  /// Deliberately loose on CONTENT (a real address has no fixed shape) and
  /// strict on SIZE. Content rules here would reject legitimate rural and
  /// multilingual addresses; the real risks are an empty box and a paste of
  /// 20k characters.
  static const int minLength = 10;
  static const int maxLength = 200;

  static final String requiredMessage = 'Address is required.';
  static final String tooShortMessage =
      'Please enter a more complete address (at least $minLength characters).';
  static final String tooLongMessage =
      'Address must be at most $maxLength characters.';

  static bool isValid(String? value) {
    if (value == null) return false;
    final v = value.trim();
    return v.length >= minLength && v.length <= maxLength;
  }

  static String? validate(String? value) {
    final v = value?.trim();
    if (v == null || v.isEmpty) return requiredMessage;
    if (v.length < minLength) return tooShortMessage;
    if (v.length > maxLength) return tooLongMessage;
    return null;
  }
}

/// Digits-only formatters, so no screen reimplements them inline.
abstract final class Formatters {
  /// For phone fields: digits only as the user types.
  static TextInputFormatter phone() => FilteringTextInputFormatter.digitsOnly;

  /// For a PIN code: digits only.
  static TextInputFormatter pincode() => FilteringTextInputFormatter.digitsOnly;

  /// OTP entry: digits only, capped at 6.
  static List<TextInputFormatter> otp() => <TextInputFormatter>[
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(6),
  ];
}
