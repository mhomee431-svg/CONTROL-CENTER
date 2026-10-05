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
  API_ENDPOINTS.INGESTION.IMPORTS,
  API_ENDPOINTS.INGESTION.IMPORT_DETAIL(1),
  API_ENDPOINTS.INGESTION.POS_INTEGRATIONS,
  API_ENDPOINTS.INGESTION.POS_INTEGRATION_DETAIL(1),
];

describe('ingestion endpoints', () => {
  it('keeps imports and POS on distinct, correctly-named routes', () => {
    expect(API_ENDPOINTS.INGESTION.IMPORTS).toBe('/api/v1/admin/imports');
    expect(API_ENDPOINTS.INGESTION.IMPORT_DETAIL(3)).toBe('/api/v1/admin/imports/3');
    expect(API_ENDPOINTS.INGESTION.POS_INTEGRATIONS).toBe('/api/v1/admin/pos-integrations');
    expect(API_ENDPOINTS.INGESTION.POS_INTEGRATION_DETAIL(3)).toBe(
      '/api/v1/admin/pos-integrations/3'
    );
  });

  it('never routes ingestion traffic through reports or shops', () => {
    // The reports endpoint exists for analytics; using it for imports produced
    // grids that could never contain a matching row.
    expect(INGESTION_ROUTES).not.toContain(API_ENDPOINTS.SYSTEM.REPORTS);
    expect(INGESTION_ROUTES).not.toContain(API_ENDPOINTS.SHOPS.LIST);
  });

  it('scopes detail routes by id', () => {
    expect(API_ENDPOINTS.INGESTION.IMPORT_DETAIL(77)).toContain('/imports/77');
    expect(API_ENDPOINTS.INGESTION.POS_INTEGRATION_DETAIL(77)).toContain('/pos-integrations/77');
  });

  it('keeps detail and list routes distinguishable', () => {
    expect(API_ENDPOINTS.INGESTION.IMPORT_DETAIL(5)).not.toBe(API_ENDPOINTS.INGESTION.IMPORTS);
    expect(API_ENDPOINTS.INGESTION.POS_INTEGRATION_DETAIL(5)).not.toBe(
      API_ENDPOINTS.INGESTION.POS_INTEGRATIONS
    );
  });
});