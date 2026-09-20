import 'package:flutter/services.dart';

/// Keyboard-level guards for the shopkeeper's numeric fields.
///
/// The backend is the authority: it bounds quantities at `le=999_999`, money at
/// `ge=0` and barcodes at 8/12/13/14 digits. These formatters only make input
/// the API would reject *impossible to type*, which removes the most common
/// avoidable round trip — a 422 for a stray letter in a price field.
///
/// They are deliberately paired with the matching `keyboardType` at the call
/// site, but they are NOT a substitute for it: many Android keypads hide the
/// decimal point, so the formatter (not the keyboard) is the actual guarantee.
/// Every helper returns a fresh list, so it can be passed straight to
/// `inputFormatters:` without sharing state between fields.
class NumericInput {
  NumericInput._();

  /// Money, percentages and distances: digits with at most [decimals] fraction
  /// digits. `''`, `'12.'` and `'.5'` stay reachable as intermediate states —
  /// the field's validator judges completeness.
  ///
  /// [allowSign] makes a single leading `-` typeable so a field whose validator
  /// explains negatives ("Price cannot be negative") can actually show that
  /// message instead of swallowing the keystroke. Fields without such a
  /// validator stay sign-free.
  ///
  /// Sanitises *anywhere* in the text (pasting `₹1,234.50` yields `1234.50`)
  /// rather than only accepting a prefix, so a correction in the middle of a
  /// number does not wipe the rest of it.
  static List<TextInputFormatter> decimal({
    int decimals = 2,
    bool allowSign = false,
  }) =>
      <TextInputFormatter>[
        _NumericTextInputFormatter(decimals: decimals, allowSign: allowSign),
      ];

  /// Whole-number counts (stock quantity, batch size, pincode).
  ///
  /// [maxLength] defaults to 6 — the backend's `le=999_999` ceiling for every
  /// quantity field — so an over-long count is stopped at the keystroke rather
  /// than after a failed save.
  static List<TextInputFormatter> whole({int maxLength = 6}) =>
      <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(maxLength),
      ];

  /// Whole numbers that may be negative: stock deltas, where `-3` removes
  /// stock. The minus sign is only accepted in the leading position.
  static List<TextInputFormatter> signedWhole({int maxLength = 6}) =>
      <TextInputFormatter>[
        _NumericTextInputFormatter(
          allowSign: true,
          decimals: null,
          maxDigits: maxLength,
        ),
      ];

  /// Signed decimals: manual latitude / longitude corrections.
  static List<TextInputFormatter> signedDecimal({int decimals = 6}) =>
      <TextInputFormatter>[
        _NumericTextInputFormatter(allowSign: true, decimals: decimals),
      ];

  /// Phone numbers and other contact identifiers.
  ///
  /// Digits plus the separators already-stored numbers use, so editing a value
  /// like `+91 98765 43210` keeps its shape instead of being flattened; letters
  /// are blocked. [maxLength] covers an international number with separators.
  static List<TextInputFormatter> phone({int maxLength = 18}) =>
      <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]')),
        LengthLimitingTextInputFormatter(maxLength),
      ];

  /// Barcode entry: strips the separators printed around a code
  /// (`8 901234 567890`) — exactly what `normalize_barcode` does server-side —
  /// and caps the field's length.
  ///
  /// Letters are deliberately LEFT in place. Silently deleting them could turn
  /// a mistyped `89O1234567890` into a different, *valid-looking* 12-digit code
  /// and look up the wrong product; keeping the typo lets the field's validator
  /// tell the shopkeeper their code is invalid instead.
  static List<TextInputFormatter> barcode({int maxLength = 20}) =>
      <TextInputFormatter>[
        FilteringTextInputFormatter.deny(RegExp(r'[\s\-]')),
        LengthLimitingTextInputFormatter(maxLength),
      ];
}

/// Sanitises a numeric field: keeps digits, at most one decimal point (with a
/// capped number of fraction digits) and, when [allowSign] is set, a single
/// leading `-`.
///
/// Unlike `FilteringTextInputFormatter.allow` with an anchored pattern — which
/// only ever accepts a *prefix* and therefore wipes the rest of the text when
/// the shopkeeper edits the middle of a number — this formatter walks the
/// whole value and drops individual characters. Pasted `₹1,234.50` becomes
/// `1234.50`; `12abc.345` becomes `12.34`.
class _NumericTextInputFormatter extends TextInputFormatter {
  const _NumericTextInputFormatter({
    this.allowSign = false,
    this.decimals = 2,
    this.maxDigits = 9,
  });

  /// Accept a single leading minus (stock deltas, manual coordinates).
  final bool allowSign;

  /// Fraction digits allowed after the decimal point; `null` forbids a point
  /// entirely (whole numbers only).
  final int? decimals;

  /// Ceiling on integer digits — keeps an accidental long keypad hold from
  /// producing a value no API would accept (quantities stop at 999,999).
  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final buffer = StringBuffer();
    var integerDigits = 0;
    var fractionDigits = 0;
    var sawPoint = false;

    for (final rune in newValue.text.runes) {
      final char = String.fromCharCode(rune);
      if (char == '-' && allowSign && buffer.isEmpty) {
        buffer.write(char);
      } else if (char == '.' && decimals != null && !sawPoint) {
        // A leading point is a valid intermediate state ('.5').
        sawPoint = true;
        buffer.write(char);
      } else if (_isDigit(char)) {
        if (sawPoint) {
          if (fractionDigits < decimals!) {
            fractionDigits++;
            buffer.write(char);
          }
        } else if (integerDigits < maxDigits) {
          integerDigits++;
          buffer.write(char);
        }
      }
    }

    final sanitised = buffer.toString();
    if (sanitised == newValue.text) return newValue;
    return TextEditingValue(
      text: sanitised,
      selection: TextSelection.collapsed(offset: sanitised.length),
    );
  }

  static bool _isDigit(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }
}