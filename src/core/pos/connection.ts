/**
 * POS CONTROL CENTER — Presentation & Capability Helpers
 *
 * Pure functions for the POS list and detail views.
 *
 * Provider-neutral by construction: every control is gated on the integration's
 * declared CAPABILITIES or on backend-advertised flags — never on a vendor name.
 * The backend stays authoritative; these helpers only derive display values.
 */

import {
  ALL_POS_CAPABILITIES,
  PosCapability,
  PosConnectionStatus,
  PosIntegrationItem,
  PosSyncResult,
} from '../types/pos';

/** The documented connection/sync states. */
const KNOWN_STATUSES: PosConnectionStatus[] = ['CONNECTED', 'DISCONNECTED', 'SYNCING', 'SYNC_FAILED'];

/** Normalize a possibly-missing status to the known lifecycle set. */
export function normalizePosStatus(status?: string | null): PosConnectionStatus | 'UNKNOWN' {
  const upper = (status || '').toUpperCase();
  return KNOWN_STATUSES.includes(upper as PosConnectionStatus) ? (upper as PosConnectionStatus) : 'UNKNOWN';
}

/** True while a sync run is currently in progress. */
export function isSyncing(item?: PosIntegrationItem | null): boolean {
  return normalizePosStatus(item?.status) === 'SYNCING';
}

/** True when the link is established. */
export function isConnected(item?: PosIntegrationItem | null): boolean {
  const status = normalizePosStatus(item?.status);
  return status === 'CONNECTED' || status === 'SYNCING';
}

/** True when the link is down. */
export function isDisconnected(item?: PosIntegrationItem | null): boolean {
  return normalizePosStatus(item?.status) === 'DISCONNECTED';
}

/** True when the most recent sync run failed. */
export function isSyncFailed(item?: PosIntegrationItem | null): boolean {
  return normalizePosStatus(item?.status) === 'SYNC_FAILED';
}

/**
 * True when the last sync is older than the freshness threshold.
 *
 * A null timestamp means "never synced", which is reported as stale so the
 * operator still sees the row as needing attention.
 */
export function isStale(
  item?: PosIntegrationItem | null,
  thresholdHours = 24,
  now: number = Date.now()
): boolean {
  if (!item) return false;
  // A live sync is never stale, whatever the clock says.
  if (isSyncing(item)) return false;
  if (!item.last_sync_at) return true;
  const last = new Date(item.last_sync_at).getTime();
  if (Number.isNaN(last)) return true;
  return now - last > thresholdHours * 60 * 60 * 1000;
}

/** Whole hours since the last sync, or null when it has never synced. */
export function hoursSinceSync(
  item?: PosIntegrationItem | null,
  now: number = Date.now()
): number | null {
  if (!item?.last_sync_at) return null;
  const last = new Date(item.last_sync_at).getTime();
  if (Number.isNaN(last)) return null;
  return Math.max(0, Math.floor((now - last) / (60 * 60 * 1000)));
}

/** Compact relative age, e.g. "3h ago", "2d ago", "never". */
export function formatSyncAge(item?: PosIntegrationItem | null, now: number = Date.now()): string {
  const hours = hoursSinceSync(item, now);
  if (hours === null) return 'Never';
  if (hours < 1) return 'Just now';
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

/**
 * True when the integration declares support for a capability.
 *
 * This is the ONLY way the UI decides whether to show a control — it is
 * deliberately independent of which vendor is behind the integration.
 */
export function hasCapability(
  capability: PosCapability | string,
  item?: PosIntegrationItem | null
): boolean {
  const caps = (item as { capabilities?: string[] } | null | undefined)?.capabilities;
  if (!Array.isArray(caps)) return false;
  return caps.some((c) => String(c).toUpperCase() === String(capability).toUpperCase());
}

/** Declared capabilities, normalized and de-duplicated. */
export function declaredCapabilities(item?: PosIntegrationItem | null): PosCapability[] {
  const caps = (item as { capabilities?: string[] } | null | undefined)?.capabilities;
  if (!Array.isArray(caps)) return [];
  const seen = new Set<string>();
  caps.forEach((c) => seen.add(String(c).toUpperCase()));
  return ALL_POS_CAPABILITIES.filter((c) => seen.has(c));
}

/**
 * Outcome for one capability stream in the latest run.
 *
 * Falls back to the rollup counters when the backend does not break the run
 * down per capability, so the UI degrades instead of showing nothing.
 */
export function resultFor(
  capability: PosCapability | string,
  item?: PosIntegrationItem | null
): PosSyncResult | null {
  const direct = item?.sync_results?.find(
    (r) => String(r.capability).toUpperCase() === String(capability).toUpperCase()
  );
  if (direct) return direct;

  // Fall back to the top-level rollup counters.
  if (!item) return null;
  const upper = String(capability).toUpperCase();
  if (upper === 'PRODUCTS') {
    return { capability: 'PRODUCTS', status: item.status === 'SYNC_FAILED' ? 'FAILED' : 'SUCCESS', records_synced: item.last_sync_products ?? null };
  }
  if (upper === 'INVENTORY') {
    return { capability: 'INVENTORY', status: item.status === 'SYNC_FAILED' ? 'FAILED' : 'SUCCESS', records_synced: item.last_sync_inventory ?? null };
  }
  return null;
}

/**
 * Manual sync trigger.
 *
 * Offered only while connected and not mid-sync, and only when the backend
 * advertises the control (default: offered).
 */
export function canTriggerSync(item?: PosIntegrationItem | null): boolean {
  if (!item) return false;
  if (item.can_trigger_sync === false) return false;
  // A sync with no declared data streams cannot do useful work. A positive
  // backend capability flag may explicitly enable integrations that report
  // capabilities through a separate endpoint.
  const hasSyncableStreams = item.can_trigger_sync === true || declaredCapabilities(item).length > 0;
  return hasSyncableStreams && isConnected(item) && !isSyncing(item);
}

/** Reconnect is offered only when the link is actually down. */
export function canReconnect(item?: PosIntegrationItem | null): boolean {
  if (!item) return false;
  if (item.can_reconnect === false) return false;
  return isDisconnected(item);
}

/**
 * Disconnect is a high-impact action.
 *
 * Offered only when connected, not mid-sync (cancelling a run would be
 * ambiguous), and never when the backend explicitly disallows it.
 */
export function canDisconnect(item?: PosIntegrationItem | null): boolean {
  if (!item) return false;
  if (item.can_disconnect === false) return false;
  return isConnected(item) && !isSyncing(item);
}

/**
 * Flatten per-capability results into stable table rows.
 * Streams with no result are omitted rather than rendered as empty rows.
 */
export function toSyncRows(item?: PosIntegrationItem | null): Array<{
  id: string;
  capability: string;
  status: string;
  records: number | null;
  error: string | null;
}> {
  if (!item) return [];
  return declaredCapabilities(item).map((capability) => {
    const result = resultFor(capability, item);
    return {
      id: `${item.id}_${capability}`,
      capability,
      status: result?.status || 'SKIPPED',
      records: result?.records_synced ?? null,
      error: result?.error_message ?? null,
    };
  });
}

/** Total records synced in the latest run across all streams. */
export function totalSynced(item?: PosIntegrationItem | null): number {
  return toSyncRows(item).reduce((sum, row) => sum + (row.records ?? 0), 0);
}
