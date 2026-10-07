import { describe, it, expect } from 'vitest';
import {
  DASHBOARD_FILTERS,
  DATE_RANGE_PARAM,
  getDashboardFilter,
  toFilterParams,
  countActiveFilters,
  isDefaultDashboardFilters,
} from '@/core/filters/dashboardFilters';

describe('dashboard filter contract', () => {
  it('declares every backend-supported dashboard filter', () => {
    const keys = DASHBOARD_FILTERS.map((f) => f.key);
    expect(keys).toContain('city');
    expect(keys).toContain('state');
    expect(keys).toContain('category');
    expect(keys).toContain('date_range');
    expect(keys).toContain('shop_status');
    expect(keys).toContain('customer_status');
  });

  it('does not render business_type until the backend advertises it', () => {
    // The prompt lists business_type as "potential"; backend has no contract yet.
    expect(DASHBOARD_FILTERS.some((f) => f.key === 'business_type')).toBe(false);
  });

  it('maps date range to the backend `days` param', () => {
    expect(DATE_RANGE_PARAM).toBe('days');
    expect(getDashboardFilter('date_range')?.param).toBe('days');
  });

  it('gives every filter a unique backend param', () => {
    const params = DASHBOARD_FILTERS.map((f) => f.param);
    expect(new Set(params).size).toBe(params.length);
  });

  it('serializes filters into backend query params', () => {
    const params = toFilterParams({
      city: 'Pune',
      state: 'Maharashtra',
      date_range: '30',
      shop_status: 'ACTIVE',
      customer_status: 'SUSPENDED',
    });
    expect(params).toEqual({
      city: 'Pune',
      state: 'Maharashtra',
      days: '30',
      shop_status: 'ACTIVE',
      customer_status: 'SUSPENDED',
    });
  });

  it('drops empty values so the backend default applies', () => {
    expect(toFilterParams({ city: '', state: undefined, category: '' })).toEqual({});
  });

  it('counts only meaningful active filters', () => {
    expect(countActiveFilters({})).toBe(0);
    expect(countActiveFilters({ city: '', date_range: '7' })).toBe(1);
    expect(isDefaultDashboardFilters({ state: '' })).toBe(true);
    expect(isDefaultDashboardFilters({ state: 'Kerala' })).toBe(false);
  });

  it('offers static options only for backend-validated enums', () => {
    const shopStatus = getDashboardFilter('shop_status');
    const city = getDashboardFilter('city');
    expect(shopStatus?.options?.map((o) => o.value)).toContain('ACTIVE');
    expect(city?.options).toBeUndefined();
    expect(city?.dynamicOptions).toBe(true);
  });
});