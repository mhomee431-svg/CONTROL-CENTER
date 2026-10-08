import { describe, it, expect } from 'vitest';
import { API_ENDPOINTS } from '@/core/api/endpoints';

/**
 * The six analytics sections each own a distinct backend route. These are
 * pinned so a section can never be pointed at another section's endpoint — a
 * mistake that renders plausible-looking numbers from the wrong dataset and is
 * invisible in the UI.
 */

const SECTION_ROUTES: Array<[string, string]> = [
  ['customers', API_ENDPOINTS.ANALYTICS.CUSTOMERS],
  ['shopkeepers', API_ENDPOINTS.ANALYTICS.SHOPKEEPERS],
  ['products', API_ENDPOINTS.ANALYTICS.PRODUCTS],
  ['businesses', API_ENDPOINTS.ANALYTICS.BUSINESSES],
  ['search', API_ENDPOINTS.ANALYTICS.SEARCH],
  ['notifications', API_ENDPOINTS.ANALYTICS.NOTIFICATIONS],
  ['geography', API_ENDPOINTS.ANALYTICS.GEOGRAPHY],
];

describe('analytics section endpoints', () => {
  it('every section has a distinct, correctly-named route', () => {
    SECTION_ROUTES.forEach(([section, route]) => {
      expect(route).toBe(`/api/v1/admin/analytics/${section}`);
    });
  });

  it('declares no duplicate routes', () => {
    const routes = SECTION_ROUTES.map(([, r]) => r);
    expect(new Set(routes).size).toBe(routes.length);
  });

  it('keeps every section off the summary and dashboard routes', () => {
    // The summary endpoint backs the overview KPIs; a section reading it would
    // report overview figures under a section heading.
    const forbidden = [
      API_ENDPOINTS.DASHBOARD.ANALYTICS_SUMMARY,
      API_ENDPOINTS.DASHBOARD.METRICS,
    ];
    SECTION_ROUTES.forEach(([, route]) => {
      expect(forbidden).not.toContain(route);
    });
  });
});
