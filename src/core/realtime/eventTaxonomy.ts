/**
 * Operational Event Taxonomy
 *
 * The spec requires that only *meaningful operational events* are streamed —
 * "Do NOT stream every database query. Only meaningful operational events
 * should be realtime."
 *
 * This module is the allowlist that enforces that. A realtime event is only
 * surfaced, rendered and allowed to trigger a dashboard refresh if its type is
 * declared here. Anything else (including raw DB/ORM noise a backend might
 * emit) is dropped at the transport boundary rather than being filtered later
 * in the view layer.
 */

export type OperationalEventType =
  | 'CUSTOMER_SEARCH'
  | 'SHOPKEEPER_REGISTRATION'
  | 'INVENTORY_UPDATE'
  | 'PRICE_UPDATE'
  | 'IMPORT_COMPLETION'
  | 'VERIFICATION_SUBMISSION'
  | 'SUPPORT_TICKET'
  | 'SHOP_UPDATE'
  | 'REGISTRATION'
  | 'VERIFICATION';

export interface OperationalEventMeta {
  type: OperationalEventType;
  label: string;
  /** Short category used for grouping in the feed. */
  group: 'DEMAND' | 'SUPPLY' | 'GOVERNANCE' | 'SUPPORT';
  description: string;
}

/**
 * The allowlist. Keys are the exact wire values accepted from the backend.
 * Adding an event type here is the only step needed to surface it.
 */
export const OPERATIONAL_EVENTS: Readonly<Record<OperationalEventType, OperationalEventMeta>> = {
  CUSTOMER_SEARCH: {
    type: 'CUSTOMER_SEARCH',
    label: 'Customer Search',
    group: 'DEMAND',
    description: 'A shopper ran a discovery search.',
  },
  SHOPKEEPER_REGISTRATION: {
    type: 'SHOPKEEPER_REGISTRATION',
    label: 'Shopkeeper Registration',
    group: 'SUPPLY',
    description: 'A new merchant completed onboarding.',
  },
  INVENTORY_UPDATE: {
    type: 'INVENTORY_UPDATE',
    label: 'Inventory Update',
    group: 'SUPPLY',
    description: 'A shop adjusted stock levels.',
  },
  PRICE_UPDATE: {
    type: 'PRICE_UPDATE',
    label: 'Price Update',
    group: 'SUPPLY',
    description: 'A listing price or offer changed.',
  },
  IMPORT_COMPLETION: {
    type: 'IMPORT_COMPLETION',
    label: 'Import Completion',
    group: 'SUPPLY',
    description: 'A bulk catalog or inventory import finished.',
  },
  VERIFICATION_SUBMISSION: {
    type: 'VERIFICATION_SUBMISSION',
    label: 'Verification Submission',
    group: 'GOVERNANCE',
    description: 'A merchant submitted documents for review.',
  },
  SUPPORT_TICKET: {
    type: 'SUPPORT_TICKET',
    label: 'Support Ticket',
    group: 'SUPPORT',
    description: 'A new complaint or support ticket was raised.',
  },
  // Legacy aliases still emitted by the existing backend contract.
  SHOP_UPDATE: {
    type: 'SHOP_UPDATE',
    label: 'Shop Update',
    group: 'SUPPLY',
    description: 'A shop record changed.',
  },
  REGISTRATION: {
    type: 'REGISTRATION',
    label: 'Registration',
    group: 'SUPPLY',
    description: 'A new account completed registration.',
  },
  VERIFICATION: {
    type: 'VERIFICATION',
    label: 'Verification',
    group: 'GOVERNANCE',
    description: 'A verification decision was recorded.',
  },
};

/** Wire values that are explicitly not operational events. */
const NON_OPERATIONAL_TYPES: ReadonlyArray<string> = [
  'QUERY',
  'DB_QUERY',
  'SQL',
  'SELECT',
  'INSERT',
  'UPDATE',
  'DELETE',
  'COMMIT',
  'ROLLBACK',
  'TRANSACTION',
  'HEARTBEAT',
  'PING',
  'PONG',
  'KEEPALIVE',
  'ACK',
  'DEBUG',
  'TRACE',
];

export function isOperationalEventType(value: string): value is OperationalEventType {
  const normalized = value.trim().toUpperCase();
  if (NON_OPERATIONAL_TYPES.includes(normalized)) return false;
  return Object.prototype.hasOwnProperty.call(OPERATIONAL_EVENTS, normalized);
}

export function getOperationalEventMeta(value: string): OperationalEventMeta | undefined {
  if (!isOperationalEventType(value)) return undefined;
  return OPERATIONAL_EVENTS[value];
}

/**
 * Event types capable of moving a dashboard KPI. Filtering the realtime
 * refresh to this set prevents a high-volume event class (e.g. every search)
 * from causing a refetch storm.
 */
export const DASHBOARD_RELEVANT_EVENT_TYPES: ReadonlyArray<OperationalEventType> = [
  'SHOPKEEPER_REGISTRATION',
  'INVENTORY_UPDATE',
  'PRICE_UPDATE',
  'IMPORT_COMPLETION',
  'VERIFICATION_SUBMISSION',
  'VERIFICATION',
  'SHOP_UPDATE',
];

export function affectsDashboard(type: string): boolean {
  if (!isOperationalEventType(type)) return false;
  return DASHBOARD_RELEVANT_EVENT_TYPES.includes(type);
}

export const EVENT_GROUPS = ['DEMAND', 'SUPPLY', 'GOVERNANCE', 'SUPPORT'] as const;
export type EventGroup = (typeof EVENT_GROUPS)[number];