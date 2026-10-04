/**
 * Extended API Endpoints for Phase 4+
 * Appended to existing endpoint map
 */

export const ANALYTICS_ENDPOINTS = {
  SUMMARY: '/api/v1/admin/analytics/summary',
  REPORTS: '/api/v1/admin/reports',
  GENERATE_REPORT: '/api/v1/admin/reports/generate',
} as const;

export const SHOPKEEPER_ENDPOINTS = {
  DETAIL: (id: number | string) => `/api/v1/shopkeeper/${id}/profile`,
  PORTAL: (id: number | string) => `/api/v1/shopkeeper/${id}/portal-summary`,
} as const;

// Analytics summary shape from backend
export interface AnalyticsSummary {
  period_days: number;
  total_searches: number;
  successful_searches: number;
  search_success_rate: number;
  unique_searchers: number;
  avg_results_per_search: number;
  top_search_terms: Array<{ term: string; count: number }>;
  top_categories_searched: Array<{ category: string; count: number }>;
  searches_by_day: Array<{ date: string; count: number }>;
  zero_result_queries: Array<{ query: string; count: number; location?: string }>;
}

export interface SubscriptionRevenueSummary {
  total_revenue: number;
  active_subscriptions: number;
  mrr: number; // monthly recurring revenue
  churn_rate: number;
  revenue_by_plan: Array<{ plan_name: string; revenue: number; count: number }>;
  revenue_by_day: Array<{ date: string; revenue: number }>;
}
