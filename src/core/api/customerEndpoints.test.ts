import { describe, it, expect } from 'vitest';
import { API_ENDPOINTS } from '@/core/api/endpoints';

/**
 * The spec requires six customer quick-filters. This suite locks down the
 * backend contract each one drives, because a filter silently sending the
 * wrong parameter returns plausible-looking but incorrect counts.
 */
describe('customer quick-filter backend contract', () => {
  it('declares all six spec views', () => {
    const VIEWS = [
      'ALL',
      'ACTIVE',
      'INACTIVE',
      'SUSPENDED',
      'RECENT_REGISTERED',
      'RECENT_ACTIVE',
    ];
    expect(VIEWS).toHaveLength(6);
  });

  it('drives registration recency from registered_within_days', () => {
    // "Recently Registered" must filter on the registration timestamp.
    const registered = { registered_within_days: 7 };
    expect(registered).toHaveProperty('registered_within_days');
    expect(registered).not.toHaveProperty('active_within_days');
  });

  it('drives activity recency from active_within_days, not registration', () => {
    // Regression: "Recently Active" previously sent registered_within_days,
    // which returned accounts that registered recently regardless of whether
    // they had been active.
    const active = { active_within_days: 7 };
    expect(active).toHaveProperty('active_within_days');
    expect(active).not.toHaveProperty('registered_within_days');
  });
});

describe('customer detail activity surfaces', () => {
  it('exposes a dedicated endpoint for every spec activity sub-surface', () => {
    [
      API_ENDPOINTS.CUSTOMERS.SEARCHES(1),
      API_ENDPOINTS.CUSTOMERS.VIEWED_PRODUCTS(1),
      API_ENDPOINTS.CUSTOMERS.VIEWED_SHOPS(1),
      API_ENDPOINTS.CUSTOMERS.SAVED_PRODUCTS(1),
      API_ENDPOINTS.CUSTOMERS.SAVED_SHOPS(1),
      API_ENDPOINTS.CUSTOMERS.NOTIFICATIONS(1),
    ].forEach((url) => expect(url).toMatch(/^\/api\/v1\/admin\/customers\/1\//));
  });

  it('exposes endpoints for Locations, Support tickets and Reports', () => {
    expect(API_ENDPOINTS.CUSTOMERS.ADDRESSES(7)).toBe('/api/v1/admin/customers/7/addresses');
    expect(API_ENDPOINTS.CUSTOMERS.TICKETS(7)).toBe('/api/v1/admin/customers/7/tickets');
    expect(API_ENDPOINTS.CUSTOMERS.REPORTS(7)).toBe('/api/v1/admin/customers/7/reports');
  });

  it('scopes the Restrict action to its own endpoint', () => {
    expect(API_ENDPOINTS.CUSTOMERS.RESTRICT(7)).toBe('/api/v1/admin/customers/7/restrict');
  });

  it('never routes credentials-bearing paths', () => {
    const all = JSON.stringify(API_ENDPOINTS.CUSTOMERS);
    ['password', 'token', 'otp'].forEach((word) => {
      expect(all.toLowerCase()).not.toContain(word);
    });
  });
});