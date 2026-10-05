import 'package:intl/intl.dart';

/// A monetary amount, stored as an integer number of **paise**.
///
/// ## Why not `double`
/// A `double` cannot represent 0.1 exactly, so summing prices drifts:
/// `0.1 + 0.2` is `0.30000000000000004`. A cart that adds ten ₹0.10 items
/// would show `₹1.0000000000000002`. Money is therefore held as an `int` of
/// paise and every operation below is integer arithmetic — exact, not
/// approximately right.
///
/// Arithmetic goes through [operator +], [operator -] and [operator *], never
/// through `double` multiplication.
///
/// ## Input
/// [fromRupees] and [fromPaise] take exact values. [parse] is the safe entry
/// point for anything arriving from the API or a widget — including a backend
/// string like `"248.50"` or `"₹1,248.00"`. Prefer a backend-supplied
/// formatted string when one is offered: it removes the client's guesswork
/// entirely.
class Money {
  /// The only field. `int` paise, never a `double`.
  final int paise;

  const Money(this.paise);

  /// Exact construction from a whole-rupee amount.
  const Money.rupees(int rupees) : paise = rupees * 100;

  /// Exact construction from paise.
  const Money.fromPaise(int paise) : paise = paise;

  static const Money zero = Money(0);

  /// The ISO code this app trades in. The backend sends `"INR"`.
  static const String currencyCode = 'INR';

  /// Indian digit grouping — `1,20,000`, not `120,000`.
  ///
  /// Pinned to `en_IN` explicitly rather than the default locale: an
  /// en-US device would otherwise render `₹120,000`, which is wrong money
  /// notation for an India-only app.
  static final NumberFormat _grouped = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  static final NumberFormat _groupedWhole = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  /// Parses a backend or user-supplied amount without float arithmetic.
  ///
  /// Accepts `248`, `248.5`, `"248.50"`, `"₹1,248.00"`, `"(−248.00)"`.
  /// Returns **null** for anything unrecognised rather than throwing or
  /// silently becoming zero — a price that renders as `₹0` because parsing
  /// failed is worse than a price that renders as "—".
  static Money? parse(Object? raw) {
    if (raw == null) return null;
    if (raw is Money) return raw;
    if (raw is int) return Money.rupees(raw);
    if (raw is double) {
      // The one unavoidable float hop, and it is guarded: rounding to the
      // nearest paise here is exact for any value the API can realistically
      // send, and all subsequent maths is integer.
      return Money((raw * 100).round());
    }
    if (raw is! String) return null;

    var s = raw.trim();
    if (s.isEmpty) return null;

    var negative = false;
    if (s.startsWith('(') && s.endsWith(')')) {
      negative = true;
      s = s.substring(1, s.length - 1).trim();
    }

    // Strip currency symbols, spaces and thousands separators. Done with a
    // character class rather than a locale parser so it cannot depend on
    // device locale.
    s = s.replaceAll(RegExp(r'[^\d.\-]'), '');
    if (s.isEmpty || s == '-' || s == '.') return null;

    final negativeBySign = s.startsWith('-');
    if (negativeBySign) s = s.substring(1);

    final parts = s.split('.');
    if (parts.length > 2) return null;
    final wholeRaw = parts[0].isEmpty ? '0' : parts[0];
    final whole = int.tryParse(wholeRaw);
    if (whole == null) return null;

    // Fraction: pad/truncate to exactly two digits (paise). Anything longer
    // than two digits is sub-paise precision and is rounded away.
    var frac = parts.length == 2 ? parts[1] : '';
    if (frac.length > 2) frac = frac.substring(0, 2);
    frac = frac.padRight(2, '0');
    final paisePart = int.tryParse(frac) ?? 0;

    var total = whole * 100 + paisePart;
    if (negative || negativeBySign) total = -total;
    return Money(total);
  }

  Money operator +(Money other) => Money(paise + other.paise);

  Money operator -(Money other) => Money(paise - other.paise);

  /// Exact only for whole-number multipliers; a fractional multiplier would
  /// reintroduce float maths, so it is rejected rather than silently rounding.
  Money operator *(int factor) => Money(paise * factor);

  bool operator >(Money other) => paise > other.paise;

  bool operator <(Money other) => paise < other.paise;

  bool operator >=(Money other) => paise >= other.paise;

  bool operator <=(Money other) => paise <= other.paise;

  bool get isZero => paise == 0;

  bool get isNegative => paise < 0;

  /// `double` view for display-only maths (e.g. a chart). Never use this to
  /// build a price — that is the whole reason [paise] is the stored type.
  double get asRupees => paise / 100;

  /// `₹248` when the amount is whole, `₹248.50` when it is not.
  ///
  /// Paise are shown only when they exist. `₹248.00` reads as though something
  /// was calculated, and a long cart full of `.00` is visual noise; but
  /// hiding a real `.50` would be lying about the amount.
  String get formatted {
    if (paise % 100 == 0) return _groupedWhole.format(paise ~/ 100);
    return _grouped.format(paise / 100);
  }

  /// Always shows two decimals — for invoices, receipts and order totals where
  /// column alignment matters more than tidiness.
  String get formattedExact => _grouped.format(paise / 100);

  /// Shown when an amount is missing or unparseable.
  static const String unknownText = '—';

  @override
  String toString() => formatted;

  @override
  bool operator ==(Object other) => other is Money && other.paise == paise;

  @override
  int get hashCode => paise.hashCode;
}

/// Formats any backend/user value as INR. Null-safe, one line at call sites.
String formatInr(Object? raw, {bool exact = false}) {
  final money = Money.parse(raw);
  if (money == null) return Money.unknownText;
  return exact ? money.formattedExact : money.formatted;
}
