import { describe, it, expect } from 'vitest';
import {
  resolvePreset,
  toDateParams,
  spanDays,
  toIsoDate,
  fromIsoDate,
  isValidCustomRange,
  normalizeRange,
  DATE_RANGE_PRESETS,
  DEFAULT_DATE_RANGE_PRESET,
  defaultCustomDraft,
  describeRange,
} from '@/core/filters/dateRange';

// Fixed clock so every assertion is deterministic.
const NOW = new Date(2026, 2, 15); // 15 Mar 2026, local time

describe('centralized analytics date range', () => {
  it('supports exactly the presets required by the spec', () => {
    expect(DATE_RANGE_PRESETS.map((p) => p.value)).toEqual([
      'today',
      'yesterday',
      '7d',
      '30d',
      '90d',
      'custom',
    ]);
    expect(DEFAULT_DATE_RANGE_PRESET).toBe('30d');
  });

  it('resolves Today to a single-day window', () => {
    const r = resolvePreset('today', undefined, NOW);
    expect(r.start).toBe('2026-03-15');
    expect(r.end).toBe('2026-03-15');
    expect(spanDays(r.start, r.end)).toBe(1);
  });

  it('resolves Yesterday to the previous day', () => {
    const r = resolvePreset('yesterday', undefined, NOW);
    expect(r.start).toBe('2026-03-14');
    expect(r.end).toBe('2026-03-14');
  });

  it('resolves 7/30/90 day windows inclusively', () => {
    expect(spanDays(resolvePreset('7d', undefined, NOW).start, resolvePreset('7d', undefined, NOW).end)).toBe(7);
    expect(spanDays(resolvePreset('30d', undefined, NOW).start, resolvePreset('30d', undefined, NOW).end)).toBe(30);
    expect(spanDays(resolvePreset('90d', undefined, NOW).start, resolvePreset('90d', undefined, NOW).end)).toBe(90);
  });

  it('always ends the window on today', () => {
    ['today', 'yesterday', '7d', '30d', '90d'].forEach((p) => {
      const r = resolvePreset(p as 'today', undefined, NOW);
      const expectedEnd = p === 'yesterday' ? '2026-03-14' : '2026-03-15';
      expect(r.end).toBe(expectedEnd);
    });
  });

  it('serializes to the backend `days` parameter', () => {
    expect(toDateParams(resolvePreset('30d', undefined, NOW))).toEqual({ days: '30' });
    expect(toDateParams(resolvePreset('today', undefined, NOW))).toEqual({ days: '1' });
  });

  it('serializes a custom range as its inclusive span', () => {
    expect(toDateParams({ preset: 'custom', start: '2026-01-01', end: '2026-01-30' })).toEqual({
      days: '30',
    });
    expect(toDateParams({ preset: 'custom', start: '2026-01-01', end: '2026-01-01' })).toEqual({
      days: '1',
    });
  });

  it('validates custom ranges', () => {
    expect(isValidCustomRange('2026-01-01', '2026-01-31')).toBe(true);
    expect(isValidCustomRange('2026-01-01', '2026-01-01')).toBe(true);
    expect(isValidCustomRange('2026-02-01', '2026-01-01')).toBe(false);
    expect(isValidCustomRange('nonsense', '2026-01-01')).toBe(false);
  });

  it('normalizes an inverted range instead of sending nonsense', () => {
    const n = normalizeRange({ preset: 'custom', start: '2026-03-10', end: '2026-03-01' });
    expect(n.start).toBe('2026-03-01');
    expect(n.end).toBe('2026-03-10');
  });

  it('round-trips ISO dates without timezone drift', () => {
    expect(toIsoDate(fromIsoDate('2026-03-15'))).toBe('2026-03-15');
  });

  it('seeds the custom draft from the trailing 30 days', () => {
    const draft = defaultCustomDraft(NOW);
    expect(draft.end).toBe('2026-03-15');
    expect(spanDays(draft.start, draft.end)).toBe(30);
  });

  it('describes a range for display', () => {
    expect(describeRange({ preset: 'custom', start: '2026-03-01', end: '2026-03-15' })).toContain('2026');
  });

  it('handles a leap-year February correctly', () => {
    const now = new Date(2024, 1, 29);
    const r = resolvePreset('7d', undefined, now);
    expect(r.end).toBe('2024-02-29');
    expect(spanDays(r.start, r.end)).toBe(7);
  });
});