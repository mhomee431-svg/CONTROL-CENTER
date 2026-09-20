/// Shop holiday models — scheduled closure days.
///
/// Distinct from the weekly schedule (open/close hours): a holiday closes the
/// shop on ONE specific date, optionally repeating every year.
class ShopHoliday {
  const ShopHoliday({
    required this.id,
    required this.date,
    this.reason,
    this.isRecurringYearly = false,
  });

  /// Parses one backend holiday row, or `null` when the row cannot be
  /// represented.
  ///
  /// A row is dropped — never patched up — when it carries no usable `id` or no
  /// parseable `holiday_date`, because:
  ///   * `id` is what the delete call and the widget keys are built from, so a
  ///     missing id is an unactionable row;
  ///   * `holiday_date` drives `isUpcoming` / `isPast` / `dateLabel`, so a
  ///     missing date cannot be displayed.
  /// Inventing either value would fabricate data, so the row is skipped
  /// instead. Skipping happens per-row (see the repository), so one malformed
  /// entry can never blank the whole Holidays screen.
  static ShopHoliday? tryParse(Map<String, dynamic> json) {
    final id = (json['id'] as num?)?.toInt();
    final date = _parseDate(json['holiday_date']);
    if (id == null || date == null) return null;
    return ShopHoliday(
      id: id,
      date: date,
      // Nullable and optional by contract (`reason` may be absent entirely).
      reason: json['reason'] as String?,
      // Enum-like addition tolerance: an unknown/absent flag means "not
      // yearly", never an exception.
      isRecurringYearly: (json['is_recurring_yearly'] as bool?) ?? false,
    );
  }

  /// Tolerant ISO-8601 date parse: `null` for absent, empty or malformed
  /// input instead of throwing. Accepts both `YYYY-MM-DD` (the contract) and a
  /// full timestamp, since `str(date)` on the server side may include time.
  static DateTime? _parseDate(Object? raw) {
    if (raw is DateTime) return raw;
    if (raw is! String || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw.trim());
  }

  final int id;

  /// Calendar day the shop is closed (backend sends `YYYY-MM-DD`).
  final DateTime date;

  /// Why the shop is closed (e.g. 'Diwali', 'Staff training').
  final String? reason;

  /// True when the closure repeats on the same calendar date every year.
  final bool isRecurringYearly;

  /// Midnight of today — the boundary for upcoming vs. past holidays.
  static DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// True when the holiday still matters: it recurs yearly, or its date is
  /// today or later. Drives the "Upcoming" filter in the UI.
  bool get isUpcoming =>
      isRecurringYearly || !date.isBefore(_today);

  /// True when the single-date closure has already passed (and it does not
  /// recur). Shown under "Past" so the list stays scannable.
  bool get isPast => !isUpcoming;

  /// Human date label, e.g. `12 Jan 2026` (matches the offer window style).
  String get dateLabel {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day.toString().padLeft(2, '0')} '
        '${months[date.month - 1]} ${date.year}';
  }
}

/// Payload for creating one holiday — normalized before hitting the API.
class HolidayDraft {
  const HolidayDraft({
    required this.date,
    this.reason,
    this.recurringYearly = false,
  });

  /// `YYYY-MM-DD` exactly as the backend expects it.
  String get encodedDate {
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '${date.year}-$m-$d';
  }

  final DateTime date;
  final String? reason;
  final bool recurringYearly;
}
