import type { ProductItem, ProductVariantItem } from '../types/admin';

/**
 * Product Quality Control — catalog-hygiene signal definitions.
 *
 * Every check here is client-derivable from the two list endpoints the
 * products area already reads (`PRODUCTS.LIST` + `IDENTIFIERS.LIST`).
 * Deliberately no new backend route: these are presentation-layer
 * observations about rows the operator can already see, not new entities the
 * backend must persist.
 *
 * A record is *absent* when the field was never reported (`null`/missing)
 * versus *present-but-bad* when a value exists and fails validation. The two
 * read differently to an operator — "never supplied" versus "supplied wrong" —
 * so absent and invalid are separate checks with separate remediation paths.
 */

/** A product row plus the variants the detail surface already resolves. */
export interface EnrichedProduct {
  product: ProductItem;
  variants: ProductVariantItem[];
}

/** Backend identifier rows: the codes that claim to point at products. */
export interface IdentifierRow {
  id: number | string;
  barcode?: string | null;
  product_id?: number | null;
  product_name?: string | null;
  status?: string | null;
}

/** One quality finding, rendered as a grid row with a drill-down to the product. */
export interface QualityFinding {
  /** Stable key: check + entity, so re-runs reconcile instead of duplicating. */
  key: string;
  productId: number;
  productName: string;
  detail: string;
}

export type QualityCheckId =
  | 'duplicates'
  | 'missing-images'
  | 'missing-brand'
  | 'missing-category'
  | 'invalid-barcode'
  | 'unmatched-identifiers'
  | 'inactive'
  | 'no-shop'
  | 'suspicious';

export interface QualityCheck {
  id: QualityCheckId;
  title: string;
  description: string;
  run: (products: EnrichedProduct[], identifiers: IdentifierRow[]) => QualityFinding[];
}

/** "Amul Taaza 500ml" and "amul  taaza 500ML" are the same product. */
export function normaliseProductName(name?: string | null): string {
  return (name || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
}

/**
 * EAN/UPC validity without a checksum library: numeric, plausible length,
 * and — where a full 8/12/13-digit payload exists — a correct GS1 check digit.
 * Short internal PLU-style codes are "unverifiable", never "invalid".
 */
export function barcodeVerdict(barcode?: string | null): 'ok' | 'missing' | 'unverifiable' | 'invalid' {
  if (barcode == null || String(barcode).trim() === '') return 'missing';
  const digits = String(barcode).replace(/[\s-]/g, '');
  if (!/^\d+$/.test(digits)) return 'invalid';
  if (digits.length < 8) return 'unverifiable';
  if (![8, 12, 13, 14].includes(digits.length)) return 'invalid';
  const body = digits.slice(0, -1).split('').map(Number);
  const check = Number(digits[digits.length - 1]);
  const sum = body.reduce((acc, d, i) => acc + d * (i % 2 === 0 ? 3 : 1), 0);
  return (10 - (sum % 10)) % 10 === check ? 'ok' : 'invalid';
}

function hasImage(p: EnrichedProduct): boolean {
  const { product, variants } = p;
  if (product.image_url) return true;
  if ((product.images || []).some(Boolean)) return true;
  return variants.some((v) => Boolean(v.image_url));
}

function mrpOf(p: ProductItem): number | null {
  const raw = p.mrp;
  if (raw == null) return null;
  const n = Number(raw);
  return Number.isFinite(n) ? n : null;
}

function nameOf(p: ProductItem): string {
  return p.name || 'Unnamed product';
}

// __CHECKS__
