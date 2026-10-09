import { describe, it, expect } from 'vitest';
import {
  classifyFreshness,
  percentOf,
  FRESH_WITHIN_HOURS,
  STALE_AFTER_HOURS,
} from './freshness';

const NOW = Date.parse('2026-01-15T12:00:00Z');
const hoursAgo = (h: number) => new Date(NOW - h * 3_600_000).toISOString();

describe('classifyFreshness', () => {
  it('reports never-updated records as UNKNOWN', () => {
    expect(classifyFreshness(null, NOW)).toBe('UNKNOWN');
    expect(classifyFreshness(undefined, NOW)).toBe('UNKNOWN');
    expect(classifyFreshness('', NOW)).toBe('UNKNOWN');
  });

  it('reports unreadable timestamps as UNKNOWN rather than guessing', () => {
    expect(classifyFreshness('not-a-date', NOW)).toBe('UNKNOWN');
  });

  it('buckets by age: FRESH <24h, RECENT 24-72h, STALE >72h', () => {
    expect(classifyFreshness(hoursAgo(0), NOW)).toBe('FRESH');
    expect(classifyFreshness(hoursAgo(FRESH_WITHIN_HOURS - 0.1), NOW)).toBe('FRESH');
    // Exact boundaries belong to the older bucket, matching the SQL the
    // backend summary uses (>= fresh_cutoff, >= cutoff, < cutoff).
    expect(classifyFreshness(hoursAgo(FRESH_WITHIN_HOURS), NOW)).toBe('RECENT');
    expect(classifyFreshness(hoursAgo(STALE_AFTER_HOURS - 0.1), NOW)).toBe('RECENT');
    expect(classifyFreshness(hoursAgo(STALE_AFTER_HOURS), NOW)).toBe('STALE');
    expect(classifyFreshness(hoursAgo(24 * 30), NOW)).toBe('STALE');
  });

  it('treats future timestamps (sync clock skew) as FRESH, not negative age', () => {
    expect(classifyFreshness(hoursAgo(-6), NOW)).toBe('FRESH');
  });
});

describe('percentOf', () => {
  it('rounds to a whole percent', () => {
    expect(percentOf(1, 3)).toBe(33);
    expect(percentOf(2, 3)).toBe(67);
    expect(percentOf(1, 4)).toBe(25);
  });

  it('returns 0 instead of dividing by zero', () => {
    expect(percentOf(0, 0)).toBe(0);
    expect(percentOf(5, -1)).toBe(0);
  });
});