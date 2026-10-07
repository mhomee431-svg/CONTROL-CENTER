import { ALL_QUALITY_CHECKS, QUALITY_CHECKS, QUALITY_CHECKS_TAIL, barcodeVerdict, normaliseProductName } from './qualityChecks';
import type { EnrichedProduct, IdentifierRow } from './qualityChecks';

function enriched(overrides: Partial<EnrichedProduct['product']> = {}, variants: EnrichedProduct['variants'] = []): EnrichedProduct {
  return {
    product: {
      id: 1, name: 'Amul Taaza 500ml', status: 'ACTIVE', shop_count: 2,
      image_url: 'https://example.test/p.png', brand_id: 1, brand_name: 'Amul',
      category_id: 1, category_name: 'Grocery', barcode: '8901234567890',
      created_at: '2024-01-01', updated_at: '2024-01-02',
      ...overrides,
    } as EnrichedProduct['product'],
    variants,
  };
}

describe('qualityChecks — nine spec checks', () => {
  it('exposes all nine checks in spec order', () => {
    expect(ALL_QUALITY_CHECKS.map((c) => c.id)).toEqual([
      'duplicates', 'missing-images', 'missing-brand', 'missing-category',
      'invalid-barcode', 'unmatched-identifiers', 'inactive', 'no-shop', 'suspicious',
    ]);
    expect(QUALITY_CHECKS.length + QUALITY_CHECKS_TAIL.length).toBe(9);
  });

  it('flags duplicate normalized names', () => {
    const a = enriched({ id: 1, name: 'Amul Taaza 500ml' });
    const b = enriched({ id: 2, name: 'amul  taaza 500ML' });
    const dupes = ALL_QUALITY_CHECKS.find((c) => c.id === 'duplicates')!.run([a, b], []);
    expect(dupeIds(dupes)).toEqual([1, 2]);
  });

  it('separates absent images from present ones', () => {
    const withImg = enriched({ id: 1 });
    const without = enriched({ id: 2, image_url: null, images: [] });
    const out = ALL_QUALITY_CHECKS.find((c) => c.id === 'missing-images')!.run([withImg, without], []);
    expect(dupeIds(out)).toEqual([2]);
  });

  it('flags missing brand / category only when both id and name are absent', () => {
    const missing = enriched({ id: 1, brand_id: null, brand_name: null, category_id: null, category_name: '' });
    const named = enriched({ id: 2, brand_id: null, brand_name: 'Amul', category_id: null, category_name: 'Grocery' });
    const brand = ALL_QUALITY_CHECKS.find((c) => c.id === 'missing-brand')!.run([missing, named], []);
    const cat = ALL_QUALITY_CHECKS.find((c) => c.id === 'missing-category')!.run([missing, named], []);
    expect(dupeIds(brand)).toEqual([1]);
    expect(dupeIds(cat)).toEqual([1]);
  });

  it('validates barcodes and flags shared ones as unmatched', () => {
    expect(barcodeVerdict('8901234567890')).toBe('ok');
    expect(barcodeVerdict(null)).toBe('missing');
    expect(barcodeVerdict('ABC123')).toBe('invalid');
    const a = enriched({ id: 1, barcode: '8901234567890' });
    const b = enriched({ id: 2, barcode: '8901234567890' });
    const invalid = ALL_QUALITY_CHECKS.find((c) => c.id === 'invalid-barcode')!.run([a, b], []);
    expect(invalid).toEqual([]);
    const unmatched = ALL_QUALITY_CHECKS.find((c) => c.id === 'unmatched-identifiers')!.run([a, b], []);
    expect(dupeIds(unmatched)).toEqual([1, 2]);
  });

  it('flags identifier rows pointing at unknown products', () => {
    const a = enriched({ id: 1 });
    const ids: IdentifierRow[] = [{ id: 9, barcode: '999', product_id: 4242, product_name: 'Ghost' }];
    const out = ALL_QUALITY_CHECKS.find((c) => c.id === 'unmatched-identifiers')!.run([a], ids);
    expect(out.map((f) => f.productId)).toEqual([4242]);
  });

  it('flags inactive, shop-less and suspicious rows', () => {
    const rows = [
      enriched({ id: 1, status: 'ARCHIVED' }),
      enriched({ id: 2, shop_count: 0 }),
      enriched({ id: 3, mrp: 0 }),
    ];
    expect(dupeIds(run('inactive', rows))).toEqual([1]);
    expect(dupeIds(run('no-shop', rows))).toEqual([2]);
    expect(dupeIds(run('suspicious', rows))).toEqual([3]);
  });

  it('normalises names for duplicate detection', () => {
    expect(normaliseProductName('Amul  Taaza-500ML')).toBe('amul taaza 500ml');
  });
});

function dupeIds(rows: { productId: number }[]): number[] {
  return rows.map((r) => r.productId).sort((a, b) => a - b);
}

function run(id: string, products: EnrichedProduct[]) {
  return ALL_QUALITY_CHECKS.find((c) => c.id === id)!.run(products, []);
}
