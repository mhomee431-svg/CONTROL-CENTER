/**
 * SUPPORT CENTER — Ticket Lifecycle & Category Helpers
 * ====================================================
 *
 * Pure presentation/classification logic shared by the ticket list, detail and
 * triage views. The backend stays authoritative for stored values; these
 * helpers only normalize, label and derive display values.
 */

import { ComplaintItem, ComplaintStatus } from '../types/admin';

/** The documented ticket lifecycle, in progression order. */
export const TICKET_STATUSES: ReadonlyArray<ComplaintStatus> = [
  'OPEN',
  'IN_PROGRESS',
  'ESCALATED',
  'RESOLVED',
  'CLOSED',
];

/**
 * Ticket categories for the filter rail. `OTHER` matches any value the
 * classifier emits that is not one of the known categories — it is never a
 * hardcoded domain assumption, just a catch-all bucket.
 */
export const TICKET_CATEGORIES = [
  'CUSTOMER',
  'SHOPKEEPER',
  'BUSINESS',
  'PRODUCT',
  'SEARCH',
  'TECHNICAL',
  'PAYMENT',
  'OTHER',
] as const;

export type TicketCategory = (typeof TICKET_CATEGORIES)[number];

const CATEGORY_SET = new Set<string>(TICKET_CATEGORIES);

/** True when the value is one of the known categories. */
export function isKnownCategory(value?: string | null): boolean {
  return CATEGORY_SET.has((value || '').toUpperCase());
}

/**
 * Derive the filter category for a ticket.
 *
 * Prefers an explicit server-side `category`; otherwise classifies from the
 * free-text `complaint_type` (e.g. "PAYMENT_FAILED" → PAYMENT). Anything
 * unmatched lands in OTHER so no ticket is ever invisible in the filter rail.
 */
export function categoryFor(ticket?: Pick<ComplaintItem, 'category' | 'complaint_type'> | null): TicketCategory {
  if (!ticket) return 'OTHER';
  const explicit = (ticket.category || '').toUpperCase();
  if (isKnownCategory(explicit)) return explicit as TicketCategory;
  const text = `${ticket.category || ''} ${ticket.complaint_type || ''}`.toUpperCase();
  for (const cat of TICKET_CATEGORIES) {
    if (cat !== 'OTHER' && text.includes(cat)) return cat;
  }
  return 'OTHER';
}

/** Human label for a category chip ("PAYMENT" → "Payment"). */
export function categoryLabel(category: string): string {
  return category.charAt(0) + category.slice(1).toLowerCase();
}

/** Normalize any status to the known lifecycle set; unknown values → null. */
export function normalizeTicketStatus(status?: string | null): ComplaintStatus | null {
  const upper = (status || '').toUpperCase();
  return TICKET_STATUSES.includes(upper as ComplaintStatus) ? (upper as ComplaintStatus) : null;
}

/** True for statuses that still need operator action. */
export function isTicketOpen(status?: string | null): boolean {
  const s = normalizeTicketStatus(status);
  return s === 'OPEN' || s === 'IN_PROGRESS' || s === 'ESCALATED';
}

/** True when the ticket reached a terminal state. */
export function isTicketClosed(status?: string | null): boolean {
  const s = normalizeTicketStatus(status);
  return s === 'RESOLVED' || s === 'CLOSED';
}

/** Full-day age buckets for the summary rail. */
export function isAged(status?: string | null, created_at?: string | null, days = 7, now: number = Date.now()): boolean {
  if (!isTicketOpen(status) || !created_at) return false;
  const created = new Date(created_at).getTime();
  if (Number.isNaN(created)) return false;
  return now - created > days * 24 * 60 * 60 * 1000;
}

/** Statuses an operator may move a ticket to from its current state. */
export function allowedTransitions(status?: string | null): ReadonlyArray<ComplaintStatus> {
  switch (normalizeTicketStatus(status)) {
    case 'OPEN':
      return ['IN_PROGRESS', 'ESCALATED', 'RESOLVED', 'CLOSED'];
    case 'IN_PROGRESS':
      return ['ESCALATED', 'RESOLVED', 'CLOSED'];
    case 'ESCALATED':
      return ['IN_PROGRESS', 'RESOLVED', 'CLOSED'];
    case 'RESOLVED':
      return ['CLOSED'];
    default:
      return [];
  }
}
