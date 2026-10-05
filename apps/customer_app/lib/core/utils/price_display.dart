import 'money.dart';

/// The three prices an offer can have, and the rules for showing them.
///
/// ## Why this exists
/// Price display was assembled ad hoc: a strikethrough MRP here, a "₹X OFF"
/// badge there, each deciding on its own whether a discount was real. The
/// failure mode that matters is not ugly — it is **a discount that isn't true**.
/// Showing "60% OFF" because `mrp` happened to be larger than `price` is a
/// fabricated claim about a real product, and on a price-comparison app that is
/// the kind of thing that ends in an enforcement notice.
///
/// ## The rule
/// A discount exists **only** when the backend supplied both numbers, both are
/// positive, and MRP is strictly greater than the current price. Anything else
/// yields `null` for [discountPercent] — not a computed guess, not a clamped
/// value, not `0%`. [hasDiscount] is the single gate every widget should check.
///
/// ## Money
/// All three figures are [Money] (integer paise). Discount percentage is
/// computed in integer arithmetic, never `((mrp - price) / mrp) * 100` on
/// doubles, which drifts.
class PriceDisplay {
  /// What the product's printed original price says. Null when not supplied.
  final Money? originalPrice;

  /// What the customer actually pays now. Null when nothing is in stock or the
  /// backend omitted it — deliberately NOT defaulted to MRP, because showing
  /// MRP as the current price misrepresents what they would pay.
  final Money? currentPrice;

  const PriceDisplay({this.originalPrice, this.currentPrice});

  /// Builds from raw backend values, whatever shape they arrive in.
  ///
  /// Zero, negative and unparseable inputs all collapse to null: the API uses
  /// `0` as "not known", and treating that as a price of ₹0 would be a lie.
  factory PriceDisplay.fromBackend({
    Object? mrp,
    Object? price,
    Object? offerPrice,
  }) {
    // `offerPrice` is preferred when supplied: when a promotion exists the
    // backend knows the real payable amount, and deriving it from mrp would
    // be exactly the guess this class exists to avoid.
    final resolvedPrice = offerPrice != null && _isUsable(offerPrice)
        ? offerPrice
        : price;
    return PriceDisplay(
      originalPrice: _usable(mrp),
      currentPrice: _usable(resolvedPrice),
    );
  }

  static bool _isUsable(Object? v) => _usable(v) != null;

  static Money? _usable(Object? raw) {
    final m = Money.parse(raw);
    if (m == null || m.paise <= 0) return null;
    return m;
  }

  /// True only when a discount is provably real.
  bool get hasDiscount {
    final from = originalPrice;
    final to = currentPrice;
    if (from == null || to == null) return false;
    // Strictly greater. An "offer" equal to MRP is no offer at all.
    if (from.paise <= to.paise) return false;
    return true;
  }

  /// Whole-percent saving, or **null** when no valid discount exists.
  ///
  /// Rounded to a whole percent because "₹9.50 OFF (3.7%)" is noise on a
  /// product card. Null is load-bearing: callers must render nothing rather
  /// than substitute a number.
  int? get discountPercent {
    if (!hasDiscount) return null;
    final from = originalPrice!.paise;
    final to = currentPrice!.paise;
    // Integer maths: ((from - to) * 100) ~/ from. Never a double division.
    final percent = ((from - to) * 100) ~/ from;
    // A 0% or negative result from valid inputs would mean the arithmetic is
    // wrong; returning null is safer than rendering a nonsense badge.
    return percent <= 0 ? null : percent;
  }

  /// Absolute amount saved, or null when no valid discount exists.
  Money? get savings => hasDiscount ? originalPrice! - currentPrice! : null;

  /// True when MRP exists but no discount can be claimed — i.e. price equals or
  /// exceeds MRP. Lets a widget show the original price WITHOUT a badge rather
  /// than hiding data that is still true.
  bool get hasOriginalButNoDiscount =>
      originalPrice != null && currentPrice != null && !hasDiscount;

  /// True when the backend gave us no usable current price at all.
  bool get hasNoCurrentPrice => currentPrice == null;
}

/// Copy for the price parts, kept beside the logic that decides they are valid.
abstract final class PriceLabels {
  static const String current = 'Price';
  static const String original = 'MRP';
  static const String offer = 'Offer price';
  static const String noCurrentPrice = 'No current price';

  /// "Save ₹99 (25% OFF)" — or empty when there is no valid discount.
  static String savingsLabel(PriceDisplay price) {
    final percent = price.discountPercent;
    final saved = price.savings;
    if (percent == null || saved == null) return '';
    return 'Save ${saved.formatted} ($percent% OFF)';
  }
}
