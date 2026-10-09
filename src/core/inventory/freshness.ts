/**
 * Inventory freshness policy — the client mirror of
 * `backend/app/core/inventory_policy.py`.
 *
 * The Control Center classifies every row from its `last_updated` timestamp
 * rather than the stored `freshness_status` column, because the sections,
 * the summary tiles and the Freshness cell must all agree: a row shown as
 * STALE has to be the same row the backend put in the STALE bucket.
 */
export const FRESH_WITHIN_HOURS = 24;
export const STALE_AFTER_HOURS = 72;

export type Freshness = 'FRESH' | 'RECENT' | 'STALE' | 'UNKNOWN';

/**
 * Buckets a record by the age of its last update:
 *   FRESH   — updated within FRESH_WITHIN_HOURS
 *   RECENT  — between the fresh and stale windows (24-72h)
 *   STALE   — older than STALE_AFTER_HOURS
 *   UNKNOWN — never updated (or an unreadable timestamp)
 *
 * `now` is injectable so tests do not depend on the wall clock. Future
 * timestamps (sync-host clock skew) count as FRESH rather than producing a
 * negative age.
 */
export function classifyFreshness(
  lastUpdated?: string | null,
  now: number = Date.now()
): Freshness {
  if (!lastUpdated) return 'UNKNOWN';
  const ts = new Date(lastUpdated).getTime();
  if (Number.isNaN(ts)) return 'UNKNOWN';
  const ageHours = Math.max(0, (now - ts) / 3_600_000);
  if (ageHours < FRESH_WITHIN_HOURS) return 'FRESH';
  if (ageHours < STALE_AFTER_HOURS) return 'RECENT';
  return 'STALE';
}

/** Rounded percentage of `part` in `total`; 0 when the total is unknown. */
export function percentOf(part: number, total: number): number {
  if (!total || total <= 0) return 0;
  return Math.round((part / total) * 100);
}