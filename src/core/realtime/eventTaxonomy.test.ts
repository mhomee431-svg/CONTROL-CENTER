import { describe, it, expect } from 'vitest';
import {
  OPERATIONAL_EVENTS,
  DASHBOARD_RELEVANT_EVENT_TYPES,
  isOperationalEventType,
  getOperationalEventMeta,
  affectsDashboard,
} from '@/core/realtime/eventTaxonomy';

describe('operational event taxonomy', () => {
  it('accepts every event class named in the spec', () => {
    [
      'CUSTOMER_SEARCH',
      'SHOPKEEPER_REGISTRATION',
      'INVENTORY_UPDATE',
      'PRICE_UPDATE',
      'IMPORT_COMPLETION',
      'VERIFICATION_SUBMISSION',
      'SUPPORT_TICKET',
    ].forEach((t) => expect(isOperationalEventType(t)).toBe(true));
  });

  it('rejects database/transport noise so it is never streamed', () => {
    // "Do NOT stream every database query."
    ['QUERY', 'DB_QUERY', 'SQL', 'SELECT', 'INSERT', 'UPDATE', 'COMMIT', 'ROLLBACK', 'HEARTBEAT', 'PING', 'ACK', 'DEBUG'].forEach(
      (t) => expect(isOperationalEventType(t)).toBe(false)
    );
  });

  it('rejects unknown event types', () => {
    expect(isOperationalEventType('SOMETHING_ELSE')).toBe(false);
    expect(isOperationalEventType('')).toBe(false);
  });

  it('matches case-insensitively and ignores surrounding whitespace', () => {
    expect(isOperationalEventType('inventory_update')).toBe(true);
    expect(isOperationalEventType('  PRICE_UPDATE  ')).toBe(true);
  });

  it('exposes metadata for rendering', () => {
    const meta = getOperationalEventMeta('CUSTOMER_SEARCH');
    expect(meta?.label).toBe('Customer Search');
    expect(meta?.group).toBe('DEMAND');
    expect(getOperationalEventMeta('NOPE')).toBeUndefined();
  });

  it('limits dashboard refetches to KPI-moving events', () => {
    expect(affectsDashboard('INVENTORY_UPDATE')).toBe(true);
    expect(affectsDashboard('VERIFICATION_SUBMISSION')).toBe(true);
    // High-volume demand events do not move a dashboard tile.
    expect(affectsDashboard('CUSTOMER_SEARCH')).toBe(false);
    expect(affectsDashboard('SUPPORT_TICKET')).toBe(false);
    expect(affectsDashboard('QUERY')).toBe(false);
  });

  it('keeps every dashboard-relevant type inside the allowlist', () => {
    DASHBOARD_RELEVANT_EVENT_TYPES.forEach((t) => {
      expect(isOperationalEventType(t)).toBe(true);
      expect(Object.keys(OPERATIONAL_EVENTS)).toContain(t);
    });
  });
});