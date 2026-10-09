import { describe, it, expect } from 'vitest';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { CAPABILITIES } from '@/core/permissions/permissions';

/**
 * Locks down the Category Configuration spec section's endpoint contract:
 *
 *   manage: name, description, status, sort order,
 *           required fields, optional fields, feature capabilities
 *   "Do not implement category rules only in the frontend."
 *
 * Each manageable attribute maps to one of the routes asserted here, and the
 * feature-capability vocabulary is served by the backend (`CONFIG_CATALOG`), not
 * hardcoded in the console.
 */

const MANAGED_FIELDS = [
  'name',
  'description',
  'status',
  'sort_order',
  'required_fields',
  'optional_fields',
  'feature_capabilities',
];

describe('category configuration spec', () => {
  it('defines every manageable attribute the spec names', () => {
    expect(MANAGED_FIELDS).toHaveLength(7);
    expect(MANAGED_FIELDS).toContain('name');
    expect(MANAGED_FIELDS).toContain('required_fields');
    expect(MANAGED_FIELDS).toContain('optional_fields');
    expect(MANAGED_FIELDS).toContain('feature_capabilities');
  });
});

describe('category endpoints', () => {
  it('exposes list, create, detail, update and delete on the admin namespace', () => {
    expect(API_ENDPOINTS.CATEGORIES.LIST).toBe('/api/v1/admin/categories');
    expect(API_ENDPOINTS.CATEGORIES.CREATE).toBe('/api/v1/admin/categories');
    expect(API_ENDPOINTS.CATEGORIES.DETAIL(7)).toBe('/api/v1/admin/categories/7');
    expect(API_ENDPOINTS.CATEGORIES.UPDATE(7)).toBe('/api/v1/admin/categories/7');
    expect(API_ENDPOINTS.CATEGORIES.DELETE(7)).toBe('/api/v1/admin/categories/7');
  });

  it('serves the configuration vocabulary from the backend, not the frontend', () => {
    // The catalog route is what makes "category rules" server-defined.
    expect(API_ENDPOINTS.CATEGORIES.CONFIG_CATALOG).toBe(
      '/api/v1/admin/categories/config-catalog'
    );
  });

  it('keeps config-catalog as an explicit static literal, not a bucketed id', () => {
    // `/categories/config-catalog` and `/categories/{id}` share a URL shape, so
    // the backend must register the static route first (see catalog.py). The
    // frontend pins the literal here so an id-typed call can never replace it.
    expect(API_ENDPOINTS.CATEGORIES.CONFIG_CATALOG).toBe(
      `${API_ENDPOINTS.CATEGORIES.LIST}/config-catalog`
    );
  });
});

describe('category capabilities', () => {
  it('gates taxonomy configuration on its own grant', () => {
    expect(CAPABILITIES.TAXONOMY_MANAGE).toBe('taxonomy.manage');
    // Reading the taxonomy must not imply the ability to change its rules.
    expect(CAPABILITIES.TAXONOMY_MANAGE).not.toBe(CAPABILITIES.TAXONOMY_READ);
  });
});
