/**
 * Search Control Center wire shapes.
 *
 * Mirrors `backend/app/api/v1/search_control.py`. Fields typed `| null` are
 * genuinely not collected by the platform (latency, failures, clicks, saves,
 * directions, engine diagnostics) — the UI must render them as "Not
 * collected", never as zero, and must never substitute client-side estimates.
 */

export interface SearchDayCount {
  date: string;
  count: number;
}

export interface SearchTopTerm {
  term: string;
  count: number;
  zero_count: number;
  zero_rate: number | null;
  avg_result_count: number | null;
}

export interface SearchFunnel {
  search_started: number;
  search_submitted: number;
  results_returned: number;
  /** Lifetime user rollups — labelled as such, not windowed figures. */
  product_opened: number;
  shop_opened: number;
  /** Not collected: honest null. */
  directions_clicked: number | null;
  saved: number | null;
  product_opened_scope: 'lifetime';
  shop_opened_scope: 'lifetime';
}

export interface SearchQualityPanel {
  success_rate: number | null;
  zero_result_rate: number | null;
  avg_result_count: number | null;
  click_rate: number | null;
  product_matching_rate: number | null;
  shop_matching_rate: number | null;
  latency_ms: number | null;
  search_failures: number | null;
}

export interface SearchControlSummary {
  period_days: number;
  window_start: string;
  window_end: string;
  volume: {
    total_searches: number;
    unique_searchers: number;
    searches_by_day: SearchDayCount[];
    zero_by_day: SearchDayCount[];
    searches_by_location: Array<{ location: string; count: number }>;
  };
  funnel: SearchFunnel;
  quality: SearchQualityPanel;
  diagnostics: {
    exact_matching: null;
    fuzzy_matching: null;
    relevance_scores: null;
    note: string;
  };
  top_searches: SearchTopTerm[];
  zero_result_queries: Array<{
    query: string;
    count: number;
    first_seen: string | null;
    last_seen: string | null;
    location: string | null;
  }>;
}

/** One catalog-gap investigation row. */
export interface ZeroResultRow {
  id: number;
  query: string;
  count: number;
  first_seen: string | null;
  last_seen: string | null;
  location: string | null;
  /** Server-computed token overlap with category names; null when no overlap. */
  potential_category: string | null;
  /** Real catalog rows sharing a token — candidates, never a recommendation. */
  candidate_products: number;
  candidate_examples: string[];
  /** Zero-result definition: always empty. */
  matched_products: [];
}

/** One per-term quality row. */
export interface SearchQualityRow {
  id: number;
  term: string;
  searches: number;
  zero_count: number;
  zero_rate: number | null;
  success_rate: number | null;
  avg_result_count: number | null;
  first_seen: string | null;
  last_seen: string | null;
}
