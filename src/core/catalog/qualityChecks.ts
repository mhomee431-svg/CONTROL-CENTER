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
  const firstWeight = body.length % 2 === 0 ? 1 : 3;
  const sum = body.reduce((acc, d, i) => acc + d * (i % 2 === 0 ? firstWeight : 4 - firstWeight), 0);
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


/**
 * The nine PRODUCT QUALITY CONTROL checks from the spec. Each `run` is a pure
 * function over rows the operator can already see — no hidden fetches, no
 * synthesized entities. Findings carry product id + name + detail so the grid
 * drills straight into the product.
 */
export const QUALITY_CHECKS: QualityCheck[] = [
  {
    id: 'duplicates',
    title: 'Duplicate candidates',
    description: 'Two or more master products normalize to the same name.',
    run: (products) => {
      const byName = new Map<string, EnrichedProduct[]>();
      products.forEach((p) => {
        const key = normaliseProductName(p.product.name);
        if (!key) return;
        const group = byName.get(key) || [];
        group.push(p);
        byName.set(key, group);
      });
      const out: QualityFinding[] = [];
      byName.forEach((group) => {
        if (group.length < 2) return;
        group.forEach((p) => {
          const others = group.filter((g) => g.product.id !== p.product.id);
          out.push({
            key: `duplicates:${p.product.id}`,
            productId: p.product.id,
            productName: nameOf(p.product),
            detail: `Same normalized name as: ${others.map((g) => `#${g.product.id}`).join(', ')}`,
          });
        });
      });
      return out;
    },
  },
  {
    id: 'missing-images',
    title: 'Missing images',
    description: 'No master image and no variant image reported.',
    run: (products) =>
      products.filter((p) => !hasImage(p)).map((p) => ({
        key: `missing-images:${p.product.id}`,
        productId: p.product.id,
        productName: nameOf(p.product),
        detail: 'No master image and no variant image reported.',
      })),
  },
  {
    id: 'missing-brand',
    title: 'Missing brand',
    description: 'No brand linkage reported on the master row.',
    run: (products) =>
      products
        .filter((p) => p.product.brand_id == null && !(p.product.brand_name || '').trim())
        .map((p) => ({
          key: `missing-brand:${p.product.id}`,
          productId: p.product.id,
          productName: nameOf(p.product),
          detail: 'No brand id and no brand name reported.',
        })),
  },
  {
    id: 'missing-category',
    title: 'Missing category',
    description: 'No category linkage reported on the master row.',
    run: (products) =>
      products
        .filter((p) => p.product.category_id == null && !(p.product.category_name || '').trim())
        .map((p) => ({
          key: `missing-category:${p.product.id}`,
          productId: p.product.id,
          productName: nameOf(p.product),
          detail: 'No category id and no category name reported.',
        })),
  },
  {
    id: 'invalid-barcode',
    title: 'Invalid barcode',
    description: 'Barcode present but failing numeric / length / check-digit validation.',
    run: (products) =>
      products
        .filter((p) => barcodeVerdict(p.product.barcode) === 'invalid')
        .map((p) => ({
          key: `invalid-barcode:${p.product.id}`,
          productId: p.product.id,
          productName: nameOf(p.product),
          detail: `Barcode ${JSON.stringify(p.product.barcode)} is not a valid EAN/UPC payload.`,
        })),
  },
];
// __CHECKS__ placeholder removed: QUALITY_CHECKS + QUALITY_CHECKS_TAIL above
// are the complete nine-check registry (see ALL_QUALITY_CHECKS).


/** Remaining checks: unmatched identifiers, inactive, no-shop, suspicious. */
export const QUALITY_CHECKS_TAIL: QualityCheck[] = [
  {
    id: 'unmatched-identifiers',
    title: 'Unmatched identifiers',
    description: 'Barcodes shared across masters, or pointing at unknown products.',
    run: (products, identifiers) => {
      const out: QualityFinding[] = [];
      const masterBarcodes = new Map<string, number[]>();
      products.forEach((p) => {
        const code = (p.product.barcode || '').trim().toLowerCase();
        if (!code) return;
        const group = masterBarcodes.get(code) || [];
        group.push(p.product.id);
        masterBarcodes.set(code, group);
      });
      masterBarcodes.forEach((ids, code) => {
        if (ids.length < 2) return;
        ids.forEach((id) => {
          const p = products.find((e) => e.product.id === id);
          out.push({
            key: `unmatched-identifiers:${id}:${code}`,
            productId: id,
            productName: p ? nameOf(p.product) : `Product #${id}`,
            detail: `Barcode shared with product(s): ${ids.filter((i) => i !== id).join(', ')}.`,
          });
        });
      });
      const known = new Set(products.map((p) => Number(p.product.id)));
      identifiers.forEach((row) => {
        const pid = row.product_id == null ? null : Number(row.product_id);
        if (pid != null && !known.has(pid)) {
          out.push({
            key: `unmatched-identifiers:row-${row.id}`,
            productId: pid,
            productName: row.product_name || `Product #${pid}`,
            detail: `Identifier points at product #${pid}, not in the master list.`,
          });
        }
      });
      return out;
    },
  },
  {
    id: 'inactive',
    title: 'Inactive products',
    description: 'Master rows sitting in an inactive status.',
    run: (products) =>
      products
        .filter((p) => ['INACTIVE', 'ARCHIVED'].includes((p.product.status || '').toUpperCase()))
        .map((p) => ({
          key: `inactive:${p.product.id}`,
          productId: p.product.id,
          productName: nameOf(p.product),
          detail: `Status is ${p.product.status}.`,
        })),
  },
  {
    id: 'no-shop',
    title: 'Products with no shop',
    description: 'Master rows with zero stocking shops reported.',
    run: (products) =>
      products
        .filter((p) => (p.product.shop_count || 0) <= 0)
        .map((p) => ({
          key: `no-shop:${p.product.id}`,
          productId: p.product.id,
          productName: nameOf(p.product),
          detail: 'No stocking shop reported.',
        })),
  },
  {
    id: 'suspicious',
    title: 'Products with suspicious data',
    description: 'Blank names, non-positive MRP, or variant prices above MRP.',
    run: (products) => {
      const out: QualityFinding[] = [];
      products.forEach((p) => {
        if (!(p.product.name || '').trim()) {
          out.push({
            key: `suspicious:${p.product.id}:name`,
            productId: p.product.id,
            productName: nameOf(p.product),
            detail: 'Product name is blank.',
          });
        }
        const mrp = mrpOf(p.product);
        if (mrp != null && mrp <= 0) {
          out.push({
            key: `suspicious:${p.product.id}:mrp`,
            productId: p.product.id,
            productName: nameOf(p.product),
            detail: `MRP is ${mrp}, expected a positive amount.`,
          });
        }
        p.variants.forEach((v) => {
          const vmrp = v.mrp == null ? null : Number(v.mrp);
          const vprice = v.price == null ? null : Number(v.price);
          if (vmrp != null && vprice != null && Number.isFinite(vmrp) && Number.isFinite(vprice) && vprice > vmrp) {
            out.push({
              key: `suspicious:${p.product.id}:variant-${v.id}`,
              productId: p.product.id,
              productName: nameOf(p.product),
              detail: 'A variant is priced above its MRP.',
            });
          }
        });
      });
      return out;
    },
  },
];

/** All nine checks in spec order. */
export const ALL_QUALITY_CHECKS: QualityCheck[] = [...QUALITY_CHECKS, ...QUALITY_CHECKS_TAIL];