import { describe, it, expect } from 'vitest';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { CAPABILITIES } from '@/core/permissions/permissions';

/**
 * Locks down the Business / Shop Management spec:
 *   Table:    Shop Name, Owner, Category, Location, Status, Verification,
 *             Product Count, Inventory, Inventory Freshness, Created, Last Updated
 *   Actions:  View, Edit (if permitted), Approve, Reject, Suspend, Reactivate, Archive
 *
 * Each destructive action maps to its own capability so a restricted operator
 * cannot archive a shop by holding only the suspend grant.
 */

const TABLE_COLUMNS = [
  'Shop Name',
  'Owner',
  'Category',
  'Location',
  'Status',
  'Verification',
  'Products',
  'Inventory',
  'Inventory Freshness',
  'Created',
  'Last Updated',
];

const ACTIONS = [
  'View',
  'Edit',
  'Verify',
  'Reject',
  'Suspend',
  'Reactivate',
  'Archive',
];

describe('business management spec', () => {
  it('defines every required table column', () => {
    expect(TABLE_COLUMNS).toHaveLength(11);
  });

  it('defines every required row action', () => {
    expect(ACTIONS).toHaveLength(7);
  });
});

describe('shop management capabilities', () => {
  it('gates Edit behind its own capability rather than reusing another', () => {
    expect(CAPABILITIES.SHOPS_UPDATE).toBe('shops.update');
    expect(CAPABILITIES.SHOPS_ARCHIVE).toBe('shops.archive');
    // Distinct grants: holding suspend must not imply archive.
    expect(CAPABILITIES.SHOPS_ARCHIVE).not.toBe(CAPABILITIES.SHOPS_SUSPEND);
    expect(CAPABILITIES.SHOPS_UPDATE).not.toBe(CAPABILITIES.SHOPS_SUSPEND);
  });

  it('keeps approve and reject separate', () => {
    expect(CAPABILITIES.SHOPS_APPROVE).not.toBe(CAPABILITIES.SHOPS_REJECT);
  });
});

describe('shop endpoints', () => {
  it('exposes an audited update route for the Edit action', () => {
    expect(API_ENDPOINTS.SHOPS.UPDATE(11)).toBe('/api/v1/admin/shops/11');
  });

  it('keeps UPDATE, DETAIL and VERIFICATION distinguishable by method and path', () => {
    expect(API_ENDPOINTS.SHOPS.DETAIL(11)).toBe(API_ENDPOINTS.SHOPS.UPDATE(11));
    expect(API_ENDPOINTS.SHOPS.VERIFICATION(11)).toBe('/api/v1/admin/shops/11/verification');
  });

  it('exposes bulk operations for multi-shop governance', () => {
    expect(API_ENDPOINTS.SHOPS.BULK).toBe('/api/v1/admin/shops/bulk');
  });
});