import { describe, it, expect } from 'vitest';
import {
  canDisconnect,
  canReconnect,
  canTriggerSync,
  declaredCapabilities,
  formatSyncAge,
  hasCapability,
  hoursSinceSync,
  isConnected,
  isDisconnected,
  isStale,
  isSyncFailed,
  isSyncing,
  normalizePosStatus,
  resultFor,
  toSyncRows,
  totalSynced,
} from './connection';
import { PosIntegrationItem, providerDisplayName } from '../types/pos';

const NOW = Date.parse('2026-03-01T12:00:00Z');

const hoursAgo = (h: number) => new Date(NOW - h * 3600_000).toISOString();

const integration = (over: Partial<PosIntegrationItem> = {}): PosIntegrationItem => ({
  id: 1,
  status: 'CONNECTED',
  ...over,
});

describe('POS connection statuses', () => {
  it('covers the four documented states', () => {
    expect(normalizePosStatus('connected')).toBe('CONNECTED');
    expect(normalizePosStatus('DISCONNECTED')).toBe('DISCONNECTED');
    expect(normalizePosStatus('Syncing')).toBe('SYNCING');
    expect(normalizePosStatus('sync_failed')).toBe('SYNC_FAILED');
  });

  it('flags unknown or missing statuses', () => {
    expect(normalizePosStatus('WEIRD')).toBe('UNKNOWN');
    expect(normalizePosStatus(null)).toBe('UNKNOWN');
  });

  it('classifies each state', () => {
    expect(isSyncing(integration({ status: 'SYNCING' }))).toBe(true);
    expect(isSyncFailed(integration({ status: 'SYNC_FAILED' }))).toBe(true);
    expect(isDisconnected(integration({ status: 'DISCONNECTED' }))).toBe(true);
    expect(isConnected(integration({ status: 'CONNECTED' }))).toBe(true);
    // A syncing integration still has a live link.
    expect(isConnected(integration({ status: 'SYNCING' }))).toBe(true);
    expect(isConnected(integration({ status: 'DISCONNECTED' }))).toBe(false);
  });
});

describe('Sync freshness', () => {
  it('treats a never-synced integration as stale', () => {
    expect(isStale(integration({}), 24, NOW)).toBe(true);
  });

  it('treats a recent sync as fresh', () => {
    expect(isStale(integration({ last_sync_at: hoursAgo(2) }), 24, NOW)).toBe(false);
  });

  it('treats a sync past the threshold as stale', () => {
    expect(isStale(integration({ last_sync_at: hoursAgo(30) }), 24, NOW)).toBe(true);
  });

  it('never marks an in-flight sync stale', () => {
    expect(isStale(integration({ status: 'SYNCING', last_sync_at: hoursAgo(99) }), 24, NOW)).toBe(false);
  });

  it('treats an unparseable timestamp as stale', () => {
    expect(isStale(integration({ last_sync_at: 'not-a-date' }), 24, NOW)).toBe(true);
  });

  it('computes hours and a compact age label', () => {
    expect(hoursSinceSync(integration({ last_sync_at: hoursAgo(5) }), NOW)).toBe(5);
    expect(formatSyncAge(integration({ last_sync_at: hoursAgo(5) }), NOW)).toBe('5h ago');
    expect(formatSyncAge(integration({ last_sync_at: hoursAgo(50) }), NOW)).toBe('2d ago');
    expect(formatSyncAge(integration({}), NOW)).toBe('Never');
  });
});

describe('Provider neutrality', () => {
  it('prefers the backend label, then the opaque code', () => {
    expect(providerDisplayName(integration({ provider_label: 'Primary Retail Cloud', provider_code: 'prc' }))).toBe(
      'Primary Retail Cloud'
    );
    expect(providerDisplayName(integration({ provider_code: 'prc' }))).toBe('prc');
    expect(providerDisplayName(integration({}))).toBe('Unassigned');
    expect(providerDisplayName(null)).toBe('Unknown Provider');
  });

  it('gates controls on declared capabilities, not the provider', () => {
    const a = integration({ provider_code: 'provider_a', capabilities: ['PRODUCTS', 'INVENTORY'] });
    const b = integration({ provider_code: 'provider_b', capabilities: ['PRICES'] });

    expect(hasCapability('PRODUCTS', a)).toBe(true);
    expect(hasCapability('PRICES', a)).toBe(false);
    // Different vendor, different capabilities — no vendor branching anywhere.
    expect(hasCapability('PRODUCTS', b)).toBe(false);
    expect(hasCapability('PRICES', b)).toBe(true);
  });

  it('normalizes and de-duplicates declared capabilities', () => {
    const item = integration({ capabilities: ['products', 'INVENTORY', 'ORDERS', 'BOGUS'] });
    expect(declaredCapabilities(item)).toEqual(['PRODUCTS', 'INVENTORY', 'ORDERS']);
    expect(declaredCapabilities(integration({ capabilities: undefined }))).toEqual([]);
  });
});

describe('Per-capability sync results', () => {
  it('returns the explicit result when the backend provides one', () => {
    const item = integration({
      capabilities: ['PRODUCTS'],
      sync_results: [{ capability: 'PRODUCTS', status: 'FAILED', records_synced: 0, error_message: 'Auth rejected' }],
    });
    const result = resultFor('PRODUCTS', item);
    expect(result?.status).toBe('FAILED');
    expect(result?.error_message).toBe('Auth rejected');
  });

  it('falls back to rollup counters when no breakdown is given', () => {
    const item = integration({ status: 'CONNECTED', last_sync_products: 120, last_sync_inventory: 340 });
    expect(resultFor('PRODUCTS', item)?.records_synced).toBe(120);
    expect(resultFor('INVENTORY', item)?.records_synced).toBe(340);
  });

  it('flattens capabilities into table rows', () => {
    const item = integration({
      capabilities: ['PRODUCTS', 'INVENTORY'],
      sync_results: [
        { capability: 'PRODUCTS', status: 'SUCCESS', records_synced: 10 },
        { capability: 'INVENTORY', status: 'FAILED', records_synced: 0 },
      ],
    });
    const rows = toSyncRows(item);
    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatchObject({ capability: 'PRODUCTS', status: 'SUCCESS', records: 10 });
    expect(rows[1]).toMatchObject({ capability: 'INVENTORY', status: 'FAILED', records: 0 });
    expect(totalSynced(item)).toBe(10);
  });

  it('returns no rows when nothing is declared', () => {
    expect(toSyncRows(integration({}))).toEqual([]);
    expect(totalSynced(null)).toBe(0);
  });
});

describe('Action gating', () => {
  it('offers sync only when connected and idle', () => {
    expect(canTriggerSync(integration({ status: 'CONNECTED' }))).toBe(true);
    expect(canTriggerSync(integration({ status: 'SYNCING' }))).toBe(false);
    expect(canTriggerSync(integration({ status: 'DISCONNECTED' }))).toBe(false);
    expect(canTriggerSync(integration({ status: 'CONNECTED', can_trigger_sync: false }))).toBe(false);
  });

  it('offers reconnect only when disconnected', () => {
    expect(canReconnect(integration({ status: 'DISCONNECTED' }))).toBe(true);
    expect(canReconnect(integration({ status: 'CONNECTED' }))).toBe(false);
    expect(canReconnect(integration({ status: 'DISCONNECTED', can_reconnect: false }))).toBe(false);
  });

  it('offers disconnect only when connected and idle', () => {
    expect(canDisconnect(integration({ status: 'CONNECTED' }))).toBe(true);
    expect(canDisconnect(integration({ status: 'SYNCING' }))).toBe(false);
    expect(canDisconnect(integration({ status: 'DISCONNECTED' }))).toBe(false);
    expect(canDisconnect(integration({ status: 'CONNECTED', can_disconnect: false }))).toBe(false);
  });
});
