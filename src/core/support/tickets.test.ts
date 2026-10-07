import { describe, it, expect } from 'vitest';
import {
  TICKET_STATUSES,
  TICKET_CATEGORIES,
  allowedTransitions,
  categoryFor,
  categoryLabel,
  isAged,
  isKnownCategory,
  isTicketClosed,
  isTicketOpen,
  normalizeTicketStatus,
} from './tickets';

describe('Ticket status helpers', () => {
  it('exposes the full documented lifecycle in order', () => {
    expect(TICKET_STATUSES).toEqual(['OPEN', 'IN_PROGRESS', 'ESCALATED', 'RESOLVED', 'CLOSED']);
  });

  it('normalizes statuses and rejects unknown values', () => {
    expect(normalizeTicketStatus('escalated')).toBe('ESCALATED');
    expect(normalizeTicketStatus('weird')).toBeNull();
    expect(normalizeTicketStatus(null)).toBeNull();
  });

  it('classifies open vs terminal states', () => {
    expect(isTicketOpen('OPEN')).toBe(true);
    expect(isTicketOpen('ESCALATED')).toBe(true);
    expect(isTicketOpen('RESOLVED')).toBe(false);
    expect(isTicketClosed('CLOSED')).toBe(true);
    expect(isTicketClosed('IN_PROGRESS')).toBe(false);
  });

  it('only permits lifecycle-legal transitions', () => {
    expect(allowedTransitions('OPEN')).toEqual(['IN_PROGRESS', 'ESCALATED', 'RESOLVED', 'CLOSED']);
    expect(allowedTransitions('IN_PROGRESS')).toEqual(['ESCALATED', 'RESOLVED', 'CLOSED']);
    expect(allowedTransitions('ESCALATED')).toEqual(['IN_PROGRESS', 'RESOLVED', 'CLOSED']);
    expect(allowedTransitions('RESOLVED')).toEqual(['CLOSED']);
    // CLOSED is terminal — no transitions at all.
    expect(allowedTransitions('CLOSED')).toEqual([]);
    expect(allowedTransitions('bogus')).toEqual([]);
  });
});

describe('Ticket category helpers', () => {
  it('exposes the documented filter categories', () => {
    expect(TICKET_CATEGORIES).toContain('PAYMENT');
    expect(TICKET_CATEGORIES).toContain('SEARCH');
  });

  it('prefers an explicit server-side category', () => {
    expect(categoryFor({ category: 'payment', complaint_type: 'OTHER_THING' })).toBe('PAYMENT');
  });

  it('derives the category from the complaint type when absent', () => {
    expect(categoryFor({ category: null, complaint_type: 'PAYMENT_FAILED' })).toBe('PAYMENT');
    expect(categoryFor({ complaint_type: 'SEARCH_RESULTS_BROKEN' })).toBe('SEARCH');
  });

  it('falls back to OTHER rather than dropping the ticket', () => {
    expect(categoryFor({ complaint_type: 'SOMETHING_ODD' })).toBe('OTHER');
    expect(categoryFor(null)).toBe('OTHER');
  });

  it('labels categories in title case', () => {
    expect(categoryLabel('IN_PROGRESS' as never)).toBe('In_progress');
    expect(categoryLabel('PAYMENT')).toBe('Payment');
  });

  it('recognizes known categories only', () => {
    expect(isKnownCategory('technical')).toBe(true);
    expect(isKnownCategory('promo')).toBe(false);
  });
});

describe('Ticket aging', () => {
  it('flags open tickets older than the threshold', () => {
    const old = new Date(Date.now() - 8 * 24 * 60 * 60 * 1000).toISOString();
    const fresh = new Date(Date.now() - 1 * 24 * 60 * 60 * 1000).toISOString();
    expect(isAged('OPEN', old)).toBe(true);
    expect(isAged('OPEN', fresh)).toBe(false);
    // Terminal tickets are never aged regardless of date.
    expect(isAged('RESOLVED', old)).toBe(false);
    expect(isAged('OPEN', null)).toBe(false);
  });
});
