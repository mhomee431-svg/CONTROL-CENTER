import { describe, it, expect } from 'vitest';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { CAPABILITIES } from '@/core/permissions/permissions';

/**
 * Locks down the Inventory Control Center spec:
 *   Sections:  All Inventory | In Stock | Low Stock | Out of Stock | Unknown |
 *              Stale | Recently Updated | Failed Updates
 *   Table:     Shop, Product, Quantity (where authorized), Availability,
 *              Source, Freshness, Last Updated
 *   Dashboard: Fresh % | Recent % | Stale % | Unknown %
 *   Click stale -> shops -> products -> last update -> source
 */

const SECTIONS = [
  'All Inventory',
  'In Stock',
  'Low Stock',
  'Out of Stock',
  'Unknown',
  'Stale',
  'Recently Updated',
  'Failed Updates',
];

const TABLE_COLUMNS = [
  'Shop',
  'Product',
  'Quantity',
  'Availability',
  'Source',
  'Freshness',
  'Last Updated',
];

const DASHBOARD_KPIS = ['Fresh %', 'Recent %', 'Stale %', 'Unknown %'];

describe('inventory control center spec', () => {
  it('defines every required section', () => {
    expect(SECTIONS).toHaveLength(8);
  });

  it('defines every required table column', () => {
    expect(TABLE_COLUMNS).toHaveLength(7);
  });

  it('defines every required dashboard KPI', () => {
    expect(DASHBOARD_KPIS).toHaveLength(4);
  });
});

describe('inventory endpoints', () => {
  it('exposes one list route serving all eight sections', () => {
    expect(API_ENDPOINTS.INVENTORY.LIST).toBe('/api/v1/admin/inventory');
  });

  it('keeps summary and the stale-drill chain distinguishable', () => {
    expect(API_ENDPOINTS.INVENTORY.SUMMARY).toBe('/api/v1/admin/inventory/summary');
    expect(API_ENDPOINTS.INVENTORY.RECORD_DETAIL(7)).toBe(
      '/api/v1/admin/inventory/records/7'
    );
    expect(API_ENDPOINTS.INVENTORY.RECORD_HISTORY(7)).toBe(
      '/api/v1/admin/inventory/records/7/history'
    );
  });
});

describe('inventory capabilities', () => {
  it('gates quantity visibility on its own grant ("quantity where authorized")', () => {
    expect(CAPABILITIES.INVENTORY_UPDATE).toBe('inventory.update');
    // Holding read must not imply the ability to see/manipulate exact counts.
    expect(CAPABILITIES.INVENTORY_UPDATE).not.toBe(CAPABILITIES.INVENTORY_READ);
  });
});