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

  factory ShopHoliday.fromJson(Map<String, dynamic> json) {
    return ShopHoliday(
      id: (json['id'] as num).toInt(),
      date: DateTime.parse(json['holiday_date'] as String),
      reason: json['reason'] as String?,
      isRecurringYearly: (json['is_recurring_yearly'] as bool?) ?? false,
    );
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
