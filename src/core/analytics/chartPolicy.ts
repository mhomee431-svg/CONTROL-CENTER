/**
 * DATA VISUALIZATION RULE — chart selection policy.
 *
 * Charts are only used where they add meaning; not every number becomes a
 * chart. This module is the single place that decides which visualization each
 * dataset earns, so individual pages cannot escalate a count into a pie chart
 * because it looks impressive.
 *
 * The rules:
 *  - Time series        -> line or area (trend over time is the meaning).
 *  - Ranked parts of a
 *    whole (top N)      -> bar (comparison across categories).
 *  - Composition with few
 *    slices             -> donut (only when the shares are the message).
 *  - A single number    -> NO chart. That is what a KPI card is for.
 */

export type ChartKind = 'line' | 'area' | 'bar' | 'donut';

export interface ChartDataset {
  /** Short axis/series label, e.g. "Registrations by day". */
  label: string;
  kind: ChartKind;
  data: Array<{ label: string; value: number }>;
}

/**
 * The analytics dataset -> chart mapping, decided once here.
 *
 * Rationale per row: a time series earns a line (its shape over time is the
 * information); a ranked top-N list earns a bar (the comparison between
 * entries is the information); a small composition earns a donut only when
 * shares matter. Nothing here is charted merely because a number exists —
 * single figures stay KPI cards in the section pages.
 */
export const SECTION_CHARTS: Record<string, ChartDataset['kind'] | null> = {
  // Customer analytics: registrations/searches per day is a trend.
  'customers:activity': 'line',
  // Registration split by city is a ranked comparison.
  'customers:by-city': 'bar',
  // Shopkeeper onboarding per day is a trend.
  'shopkeepers:onboarding': 'area',
  // Products added per day is a trend.
  'products:additions': 'line',
  // Catalog composition by category — shares are the message.
  'products:by-category': 'donut',
  // New shops per day is a trend.
  'businesses:new-shops': 'area',
  // Shops by city is a ranked comparison (density).
  'businesses:by-city': 'bar',
  // Search volume per day is the core search trend.
  'search:volume': 'line',
  // Geography: shop density by city is a ranked comparison.
  'geography:shop-density': 'bar',
  // Notification dispatch per day is a trend.
  'notifications:dispatch': 'area',
};

/** Resolve the chart kind a dataset earns, or null when it earns none. */
export function chartKindFor(key: string): ChartKind | null {
  return SECTION_CHARTS[key] ?? null;
}
