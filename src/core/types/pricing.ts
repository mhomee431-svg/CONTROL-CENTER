/**
 * Price Management types — `/api/v1/admin/pricing/summary` and
 * `/api/v1/admin/pricing/history`.
 *
 * Mirrors `backend/app/api/v1/pricing.py`. Prices are plain decimal numbers.
 * `null` means "not recorded" and is rendered as an em dash rather than `0`,
 * so an absent price is never shown as though the item were free.
 */

/** A single figure for one of the summary tiles (Current Price / MRP / Offer). */
export interface PriceSummaryStat {
  /** Human-facing tile label, e.g. "CURRENT PRICE". */
  label: string;
  /** How many inventory rows carry this value. */
  count: number;
  /** Share of the priced base as a percentage (0–100), or null when the base is empty. */
  percent: number | null;
}

/** Response body of `/api/v1/admin/pricing/summary` (`data`). */
export interface PriceSummary {
  /** Currency code shown beside monetary figures (from the platform settings). */
  currency: string;
  /** Total inventory rows considered. */
  total_items: number;
  /** Rows that have at least one price recorded. */
  priced_items: number;
  /** The three "show if available" tiles. */
  stats: {
    current_price: PriceSummaryStat;
    mrp: PriceSummaryStat;
    offer_price: PriceSummaryStat;
  };
  /** Rows priced strictly below MRP (a real discount). */
  discounted_items: number;
  /** Total recorded price-change events across the platform. */
  price_changes: number;
  /** ISO-8601 timestamp of the most recent recorded change, or null when none. */
  last_change_at: string | null;
}

/** One row of the Price detail table — a single recorded price change. */
export interface PriceHistoryItem {
  id: number;
  shop_id: number;
  shop_name: string | null;
  product_id: number | null;
  product_name: string | null;
  old_price: number | null;
  new_price: number | null;
  mrp: number | null;
  changed_by: string | null;
  changed_at: string | null;
  source: string;
}

/** Paginated response of `/api/v1/admin/pricing/history` (`data`). */
export interface PriceHistoryResponse {
  items: PriceHistoryItem[];
  total: number;
}
