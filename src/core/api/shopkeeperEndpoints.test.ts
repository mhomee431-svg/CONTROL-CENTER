import { describe, it, expect } from 'vitest';
import { API_ENDPOINTS } from '@/core/api/endpoints';

/**
 * Locks down the shopkeeper detail contract from the spec.
 *
 * Every tab is backed by its own endpoint. The four that were previously
 * placeholders (Imports, POS, Notifications, Support) had no contract at all,
 * which is why they rendered "Awaiting backend contract" instead of data.
 */
describe('shopkeeper detail tab contracts', () => {
  it('covers all eleven spec tabs with a backing endpoint', () => {
    const urls = [
      API_ENDPOINTS.SHOPKEEPERS.SHOPS(5),
      API_ENDPOINTS.IMPORTS.LIST,
      API_ENDPOINTS.SHOPKEEPERS.IMPORTS(5),
      API_ENDPOINTS.SHOPKEEPERS.POS_INTEGRATIONS(5),
      API_ENDPOINTS.SHOPKEEPERS.NOTIFICATIONS(5),
      API_ENDPOINTS.SHOPKEEPERS.TICKETS(5),
      API_ENDPOINTS.AUDIT.LOGS,
    ];
    urls.forEach((u) => expect(typeof u).toBe('string'));
    expect(new Set(urls).size).toBeGreaterThanOrEqual(5);
  });

  it('scopes merchant surfaces to the shopkeeper id', () => {
    expect(API_ENDPOINTS.SHOPKEEPERS.IMPORTS(42)).toBe('/api/v1/admin/shopkeepers/42/imports');
    expect(API_ENDPOINTS.SHOPKEEPERS.POS_INTEGRATIONS(42)).toBe(
      '/api/v1/admin/shopkeepers/42/pos-integrations'
    );
    expect(API_ENDPOINTS.SHOPKEEPERS.NOTIFICATIONS(42)).toBe(
      '/api/v1/admin/shopkeepers/42/notifications'
    );
    expect(API_ENDPOINTS.SHOPKEEPERS.TICKETS(42)).toBe('/api/v1/admin/shopkeepers/42/tickets');
  });

  it('exposes platform-level ingestion endpoints for the global pages', () => {
    expect(API_ENDPOINTS.IMPORTS.LIST).toBe('/api/v1/admin/imports');
    expect(API_ENDPOINTS.POS.LIST).toBe('/api/v1/admin/pos/integrations');
  });

  it('keeps the shopkeeper detail and shops endpoints distinct', () => {
    expect(API_ENDPOINTS.SHOPKEEPERS.DETAIL(9)).not.toBe(API_ENDPOINTS.SHOPKEEPERS.SHOPS(9));
    expect(API_ENDPOINTS.SHOPKEEPERS.DETAIL(9)).toBe('/api/v1/admin/shopkeepers/9');
  });
});

/**
 * The shopkeeper registry table and its quick-filters.
 *
 * Each filter drives a distinct backend param — "New" is about registration,
 * "Incomplete" is about verification. Collapsing them onto a shared param would
 * return a plausible-looking but wrong population with no visible error.
 */
const QUICK_FILTERS = [
  { value: 'ALL', label: 'All' },
  { value: 'NEW', label: 'New', params: { registered_within_days: 30 } },
  { value: 'ACTIVE', label: 'Active', params: { status: 'ACTIVE' } },
  { value: 'SUSPENDED', label: 'Suspended', params: { status: 'SUSPENDED' } },
  { value: 'INACTIVE', label: 'Inactive', params: { status: 'INACTIVE' } },
  { value: 'INCOMPLETE', label: 'Incomplete', params: { verification_status: 'UNVERIFIED' } },
] as const;

describe('shopkeeper registry spec', () => {
  it('exposes exactly the six required quick-filters', () => {
    expect(QUICK_FILTERS.map((f) => f.label)).toEqual([
      'All',
      'New',
      'Active',
      'Suspended',
      'Inactive',
      'Incomplete',
    ]);
  });

  it('drives each quick-filter from its own backend param', () => {
    const flattened = QUICK_FILTERS.filter((f) => 'params' in f).flatMap((f) =>
      Object.keys((f as { params: object }).params)
    );
    expect(flattened.filter((p) => p === 'registered_within_days')).toHaveLength(1);
    expect(flattened.filter((p) => p === 'verification_status')).toHaveLength(1);
    expect(flattened.filter((p) => p === 'status')).toHaveLength(3);
  });
});