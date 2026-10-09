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

  /**
   * Optional extended analytics surfaces. The backend includes these when the
   * corresponding analytics modules are enabled; the UI renders each one only
   * when present and degrades gracefully otherwise.
   */
  /** Geography: searches grouped by region/locality. */
  searches_by_location?: Array<{ location: string; count: number }> | null;
  /** Engagement: notifications dispatched in the period, with channel split. */
  notifications_sent?: number | null;
  notifications_by_type?: Array<{ type: string; count: number }> | null;
  /** Platform operations: ingestion/POS/system health counters. */
  imports_completed?: number | null;
  imports_failed?: number | null;
  pos_sync_failures?: number | null;
}

export interface SubscriptionRevenueSummary {
  // Mirrors GET /api/v1/admin/analytics/summary. Currently unused while the
  // subscriptions refresh work is being scoped — kept as the contract the
  // future revenue tiles will read, so the design stays close at hand.
  total_revenue: number;
  active_subscriptions: number;
  mrr: number; // monthly recurring revenue
  churn_rate: number;
  revenue_by_plan: Array<{ plan_name: string; revenue: number; count: number }>;
  revenue_by_day: Array<{ date: string; revenue: number }>;
}

/**
 * Section analytics response shapes.
 *
 * These mirror the backend `/api/v1/admin/analytics/*` contracts exactly. Where
 * the platform does not collect a metric, the field is `null` — never `0` — so
 * the UI can distinguish "not collected" from "genuinely zero".
 */

/** A single zero-filled day in a trend series. */
export interface AnalyticsDayPoint {
  date: string;
  count: number;
}

/** Shared window metadata every section response carries. */
export interface AnalyticsWindow {
  period_days: number;
  window_start: string;
  window_end: string;
}

/** Customer analytics — `/analytics/customers`. */
export interface CustomerAnalytics extends AnalyticsWindow {
  new_customers: number;
  previous_new_customers: number;
  registration_growth_rate: number | null;
  active_users: number;
  returning_users: number;
  total_customers: number;
  suspended_customers: number;
  restricted_customers: number;
  retention_rate: number | null;
  retention_eligible_base: number;
  searches: number;
  unique_searchers: number;
  product_views: number;
  shop_views: number;
  /** Not collected by the platform — reported as null, never zero. */
  directions: number | null;
  favorites: number;
  registrations_by_day: Array<{ date: string; registrations: number; searches: number }>;
  registrations_by_city: Array<{ city: string; count: number }>;
  customers_by_status: Array<{ status: string; count: number }>;
}

/** Shopkeeper analytics — `/analytics/shopkeepers`. */
export interface ShopkeeperAnalytics extends AnalyticsWindow {
  new_shopkeepers: number;
  previous_new_shopkeepers: number;
  shopkeeper_growth_rate: number | null;
  active_shopkeepers: number;
  total_shopkeepers: number;
  active_businesses: number;
  product_additions: number;
  inventory_updates: number;
  price_updates: number;
  imports_completed: number;
  imports_failed: number;
  pos_sync_success: number;
  pos_sync_failures: number;
  shopkeepers_by_day: AnalyticsDayPoint[];
  top_merchants: Array<{ owner_id: number; name: string; shops: number }>;
  verification_breakdown: Array<{ status: string; count: number }>;
}

/** Product analytics — `/analytics/products`. */
export interface ProductAnalytics extends AnalyticsWindow {
  total_products: number;
  active_products: number;
  pending_products: number;
  products_with_no_shop: number;
  products_with_stale_inventory: number;
  low_coverage_products: number;
  top_searched_products: Array<{ id: number; name: string; count: number }>;
  top_viewed_products: Array<{ id: number; name: string; count: number }>;
  most_available_products: Array<{ id: number; name: string; count: number }>;
  products_by_category: Array<{ category: string; count: number }>;
  products_added_by_day: AnalyticsDayPoint[];
}

/** Business analytics — `/analytics/businesses`. */
export interface BusinessAnalytics extends AnalyticsWindow {
  total_shops: number;
  active_shops: number;
  new_shops: number;
  pending_shops: number;
  fresh_shops: number;
  stale_shops: number;
  average_product_coverage: number;
  shops_by_category: Array<{ category: string; count: number }>;
  shops_by_city: Array<{ city: string; count: number }>;
  top_coverage_shops: Array<{ id: number; name: string; products: number }>;
  new_shops_by_day: AnalyticsDayPoint[];
}

/** Search analytics — `/analytics/search`. */
export interface SearchAnalytics extends AnalyticsWindow {
  total_searches: number;
  successful_searches: number;
  zero_result_searches: number;
  search_success_rate: number | null;
  unique_searchers: number;
  product_opens: number;
  shop_opens: number;
  /** Direction clicks are not collected — reported as null. */
  directions: number | null;
  top_search_terms: Array<{ term: string; count: number }>;
  zero_result_queries: Array<{ query: string; count: number }>;
  searches_by_day: AnalyticsDayPoint[];
}

/** Notification analytics — `/analytics/notifications`. */
export interface NotificationAnalytics extends AnalyticsWindow {
  total_campaigns: number;
  campaigns_sent: number;
  recipients_total: number;
  recipients_sent: number;
  recipients_failed: number;
  /** Delivery / open / click are not collected — reported as null. */
  recipients_delivered: number | null;
  recipients_opened: number | null;
  recipients_clicked: number | null;
  campaigns_by_status: Array<{ status: string; count: number }>;
  campaigns_by_audience: Array<{ audience: string; count: number }>;
  campaigns_sent_by_day: AnalyticsDayPoint[];
}

/** Geographic analytics — `/analytics/geography`. */
export interface GeographyAnalytics extends AnalyticsWindow {
  covered_cities: number;
  covered_states: number;
  shops_by_city: Array<{ city: string; count: number }>;
  shops_by_state: Array<{ state: string; count: number }>;
  customers_by_city: Array<{ city: string; count: number }>;
  searches_by_location: Array<{ location: string; count: number }>;
  category_density: Array<{ city: string; category: string; count: number }>;
  demand_coverage: Array<{
    city: string;
    shops: number;
    searches: number;
    demand_per_shop: number | null;
  }>;
}
