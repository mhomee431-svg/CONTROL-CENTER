/**
 * Centralized Analytics Date Range
 *
 * Single source of truth for every date-range control in the Admin Control
 * Center. Presets, custom ranges and request serialization all live here so no
 * component ever hardcodes "7 / 30 / 90" or its own date arithmetic.
 *
 * Supported (per spec): Today, Yesterday, 7 Days, 30 Days, 90 Days, Custom.
 *
 * Backend contract: the analytics summary accepts `?days=N`. A custom range is
 * therefore sent as `days` = the inclusive day span it covers, so the backend
 * applies its own default logic instead of receiving an unrecognised shape.
 */

export type DateRangePreset =
  | 'today'
  | 'yesterday'
  | '7d'
  | '30d'
  | '90d'
  | 'custom';

export interface SelectOption {
  value: string;
  label: string;
}

/** ISO calendar date (YYYY-MM-DD) in the operator's local timezone. */
export type IsoDate = string;

export interface DateRange {
  preset: DateRangePreset;
  /** Inclusive start of the reporting window. */
  start: IsoDate;
  /** Inclusive end of the reporting window. */
  end: IsoDate;
}

/** Default window, matching the backend's own 30-day analytics default. */
export const DEFAULT_DATE_RANGE_PRESET: DateRangePreset = '30d';

export const DATE_RANGE_PRESETS: SelectOption[] = [
  { value: 'today', label: 'Today' },
  { value: 'yesterday', label: 'Yesterday' },
  { value: '7d', label: '7 Days' },
  { value: '30d', label: '30 Days' },
  { value: '90d', label: '90 Days' },
  { value: 'custom', label: 'Custom Range' },
];

/**
 * Day OFFSETS from today for each relative preset. The window is inclusive, so
 * an offset of 6 yields a 7-day window (today plus the previous 6 days).
 */
/**
 * Inclusive window definition per preset, expressed as day offsets from today.
 *
 * Both endpoints are needed: 'yesterday' shifts start AND end back by one day,
 * whereas '7d' shifts only the start (today plus the previous 6 days).
 */
export const RELATIVE_PRESET_WINDOWS: Record<
  Exclude<DateRangePreset, 'custom'>,
  { startOffset: number; endOffset: number }
> = {
  today: { startOffset: 0, endOffset: 0 },
  yesterday: { startOffset: -1, endOffset: -1 },
  '7d': { startOffset: -6, endOffset: 0 },
  '30d': { startOffset: -29, endOffset: 0 },
  '90d': { startOffset: -89, endOffset: 0 },
};

function pad(n: number): string {
  return String(n).padStart(2, '0');
}

/** Formats a Date as a local (not UTC) ISO calendar date. */
export function toIsoDate(date: Date): IsoDate {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

/** Parses YYYY-MM-DD into a local Date at midnight. */
export function fromIsoDate(iso: IsoDate): Date {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(y, (m || 1) - 1, d || 1);
}

/**
 * Inclusive day span between two ISO dates.
 * `span('2026-01-01', '2026-01-30') === 30` — the count the backend's `days`
 * parameter expects for the same window.
 */
export function spanDays(start: IsoDate, end: IsoDate): number {
  const ms = fromIsoDate(end).getTime() - fromIsoDate(start).getTime();
  if (!Number.isFinite(ms) || ms < 0) return 0;
  return Math.floor(ms / 86_400_000) + 1;
}

/** Resolves a preset into concrete dates. `custom` requires explicit dates. */
export function resolvePreset(
  preset: DateRangePreset,
  custom?: { start: IsoDate; end: IsoDate },
  now: Date = new Date()
): DateRange {
  if (preset === 'custom') {
    const start = custom?.start ?? toIsoDate(now);
    const end = custom?.end ?? start;
    return normalizeRange({ preset, start, end });
  }

  const { startOffset, endOffset } = RELATIVE_PRESET_WINDOWS[preset];
  const startDate = new Date(now);
  startDate.setDate(startDate.getDate() + startOffset);
  const endDate = new Date(now);
  endDate.setDate(endDate.getDate() + endOffset);

  return {
    preset,
    start: toIsoDate(startDate),
    end: toIsoDate(endDate),
  };
}

/** Orders dates and clamps an inverted range so start never exceeds end. */
export function normalizeRange(range: DateRange): DateRange {
  if (range.start <= range.end) return range;
  return { ...range, start: range.end, end: range.start };
}

/**
 * Converts a range into backend query params.
 * `days` is the inclusive span, which is exactly what the analytics endpoint
 * expects.
 */
export function toDateParams(range: DateRange): Record<string, string> {
  const days = spanDays(range.start, range.end);
  return days > 0 ? { days: String(days) } : {};
}

/** True when the two ranges describe the same window. */
export function isSameRange(a: DateRange, b: DateRange): boolean {
  return a.start === b.start && a.end === b.end;
}

/** True when a preset's dates are still valid to submit. */
export function isValidCustomRange(start: IsoDate, end: IsoDate): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(start) || !/^\d{4}-\d{2}-\d{2}$/.test(end)) return false;
  const s = fromIsoDate(start).getTime();
  const e = fromIsoDate(end).getTime();
  return Number.isFinite(s) && Number.isFinite(e) && s <= e;
}

/** Default custom-range draft: the trailing 30 days ending today. */
export function defaultCustomDraft(now: Date = new Date()): { start: IsoDate; end: IsoDate } {
  const r = resolvePreset('30d', undefined, now);
  return { start: r.start, end: r.end };
}

/** Human summary for display, e.g. "1 Mar 2026 – 30 Mar 2026". */
export function describeRange(range: DateRange): string {
  const fmt = (iso: IsoDate) =>
    fromIsoDate(iso).toLocaleDateString(undefined, {
      day: 'numeric',
      month: 'short',
      year: 'numeric',
    });
  return `${fmt(range.start)} – ${fmt(range.end)}`;
}