/**
 * POS CONTROL CENTER — Provider-Neutral Integration Models
 * =======================================================
 *
 * DESIGN RULE: the Admin UI is never coupled to a single POS vendor.
 *
 * No vendor name, product name, or vendor-specific field appears anywhere in
 * these models or in the UI. Integrations are described only by:
 *
 *   - `provider_code`  an opaque, backend-assigned identifier (e.g. "provider_a")
 *                      rendered as a neutral label, never interpreted client-side.
 *   - `capabilities`   the feature flags the integration actually supports,
 *                      e.g. ["PRODUCTS", "INVENTORY", "PRICE", "ORDERS"].
 *
 * The UI enables/disables controls by checking CAPABILITY strings, never by
 * branching on a vendor. Adding a new vendor is a backend concern only and
 * requires zero frontend changes.
 */

/**
 * Connection + sync lifecycle for an integration.
 *
 * CONNECTED / DISCONNECTED describe the link itself;
 * SYNCING / FAILED describe the most recent sync run.
 */
export type PosConnectionStatus =
  | 'CONNECTED'
  | 'DISCONNECTED'
  | 'SYNCING'
  | 'SYNC_FAILED';

/**
 * Neutral capability vocabulary. A provider may support any subset.
 * These are intentionally generic platform concepts, not vendor features.
 */
export const POS_CAPABILITIES = {
  /** Push/pull the product master catalog. */
  PRODUCTS: 'PRODUCTS',
  /** Push/pull per-shop stock levels. */
  INVENTORY: 'INVENTORY',
  /** Push/pull prices and MRP. */
  PRICES: 'PRICES',
  /** Import orders for analytics. */
  ORDERS: 'ORDERS',
} as const;

export type PosCapability = (typeof POS_CAPABILITIES)[keyof typeof POS_CAPABILITIES];

export const ALL_POS_CAPABILITIES: ReadonlyArray<PosCapability> = Object.values(POS_CAPABILITIES);

/** One sync run for one capability stream. */
export interface PosSyncResult {
  capability: PosCapability | string;
  status: 'SUCCESS' | 'FAILED' | 'SKIPPED' | 'RUNNING' | string;
  records_synced?: number | null;
  error_message?: string | null;
  started_at?: string | null;
  finished_at?: string | null;
}

export interface PosIntegrationItem {
  id: number;
  shop_id?: number | null;
  shop_name?: string | null;

  /**
   * Opaque backend-assigned provider identifier. Treated as an opaque label —
   * the client never branches on its value.
   */
  provider_code?: string | null;
  /** Optional human-facing label supplied by the backend, still vendor-neutral. */
  provider_label?: string | null;

  /**
   * Capability flags this integration supports, e.g. ["PRODUCTS","INVENTORY"].
   * The UI gates every control on this list — never on the provider.
   */
  capabilities?: string[];

  status: PosConnectionStatus | string;
  last_sync_at?: string | null;

  /** Rollup counters surfaced in the grid. */
  products_synced?: number | null;
  inventory_synced?: number | null;

  /** Counters for the most recent sync run. */
  last_sync_products?: number | null;
  last_sync_inventory?: number | null;

  /** Per-capability outcome of the latest run. */
  sync_results?: PosSyncResult[];

  connected_at?: string | null;
  error_message?: string | null;

  /** Backend-advertised controls; honoured when explicitly false. */
  can_trigger_sync?: boolean;
  can_disconnect?: boolean;
  can_reconnect?: boolean;
}

/**
 * Display label for a provider.
 *
 * Prefers the backend's neutral human label, falls back to the opaque code.
 * No vendor branding is synthesised on the client.
 */
export function providerDisplayName(item?: PosIntegrationItem | null): string {
  if (!item) return 'Unknown Provider';
  const label = item.provider_label?.trim();
  if (label) return label;
  const code = item.provider_code?.trim();
  if (code) return code;
  return 'Unassigned';
}
