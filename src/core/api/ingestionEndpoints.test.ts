import { describe, it, expect } from 'vitest';
import { API_ENDPOINTS } from '@/core/api/endpoints';

/**
 * Regression guard for cross-endpoint mismatches.
 *
 * Three surfaces previously read an unrelated endpoint and rendered silently
 * blank or wrong results because the payloads share no fields:
 *   - imports list + detail  -> /admin/reports
 *   - pos list + detail      -> /admin/shops
 *   - global search: IMPORT  -> /admin/reports
 *
 * These assertions fail loudly if a screen is ever pointed at the wrong source.
 */

const INGESTION_ROUTES = [
  API_ENDPOINTS.IMPORTS.LIST,
  API_ENDPOINTS.IMPORTS.DETAIL(1),
  API_ENDPOINTS.POS.LIST,
  API_ENDPOINTS.POS.DETAIL(1),
];

describe('ingestion endpoints', () => {
  it('keeps imports and POS on distinct, correctly-named routes', () => {
    expect(API_ENDPOINTS.IMPORTS.LIST).toBe('/api/v1/admin/imports');
    expect(API_ENDPOINTS.IMPORTS.DETAIL(3)).toBe('/api/v1/admin/imports/3');
    expect(API_ENDPOINTS.POS.LIST).toBe('/api/v1/admin/pos/integrations');
    expect(API_ENDPOINTS.POS.DETAIL(3)).toBe('/api/v1/admin/pos/integrations/3');
  });

  it('never routes ingestion traffic through reports or shops', () => {
    // The reports endpoint exists for analytics; using it for imports produced
    // grids that could never contain a matching row.
    expect(INGESTION_ROUTES).not.toContain(API_ENDPOINTS.SYSTEM.REPORTS);
    expect(INGESTION_ROUTES).not.toContain(API_ENDPOINTS.SHOPS.LIST);
  });

  it('scopes detail routes by id', () => {
    expect(API_ENDPOINTS.IMPORTS.DETAIL(77)).toContain('/imports/77');
    expect(API_ENDPOINTS.POS.DETAIL(77)).toContain('/pos/integrations/77');
  });

  it('keeps detail and list routes distinguishable', () => {
    expect(API_ENDPOINTS.IMPORTS.DETAIL(5)).not.toBe(API_ENDPOINTS.IMPORTS.LIST);
    expect(API_ENDPOINTS.POS.DETAIL(5)).not.toBe(API_ENDPOINTS.POS.LIST);
  });

  it('keeps the import job actions scoped under their job', () => {
    // Retry and cancel are per-job. A route that lost its id would act on an
    // arbitrary job, so they are pinned here rather than left to convention.
    expect(API_ENDPOINTS.IMPORTS.RETRY(9)).toBe('/api/v1/admin/imports/9/retry');
    expect(API_ENDPOINTS.IMPORTS.CANCEL(9)).toBe('/api/v1/admin/imports/9/cancel');
    expect(API_ENDPOINTS.IMPORTS.ERRORS(9)).toBe('/api/v1/admin/imports/9/errors');
  });

  it('keeps the POS connection actions scoped under their integration', () => {
    expect(API_ENDPOINTS.POS.SYNC(9)).toBe('/api/v1/admin/pos/integrations/9/sync');
    expect(API_ENDPOINTS.POS.DISCONNECT(9)).toBe('/api/v1/admin/pos/integrations/9/disconnect');
    expect(API_ENDPOINTS.POS.RECONNECT(9)).toBe('/api/v1/admin/pos/integrations/9/reconnect');
    expect(API_ENDPOINTS.POS.SYNC_HISTORY(9)).toBe('/api/v1/admin/pos/integrations/9/syncs');
  });
});