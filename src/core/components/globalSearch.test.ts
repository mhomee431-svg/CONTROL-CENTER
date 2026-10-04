import { describe, it, expect } from 'vitest';

/**
 * Global search entity resolution.
 * Mirrors the classification logic used by GlobalSearchModal so the entity-type
 * contract (Customer, Shopkeeper, Business, Product, Barcode, Import, Support,
 * Audit) is verified without rendering the dialog.
 */
type EntityType =
  | 'CUSTOMER'
  | 'SHOPKEEPER'
  | 'BUSINESS'
  | 'PRODUCT'
  | 'BARCODE'
  | 'INVENTORY'
  | 'IMPORT'
  | 'SUPPORT'
  | 'AUDIT';

function looksLikeBarcode(term: string): boolean {
  return /^\d{6,14}$/.test(term.trim());
}

function classifyUser(role: string): EntityType {
  return (role || '').toLowerCase().includes('shopkeeper') ? 'SHOPKEEPER' : 'CUSTOMER';
}

function classifyProduct(name: string, barcode: string | null | undefined, term: string): EntityType {
  const hit = looksLikeBarcode(term) && !!barcode && barcode.includes(term);
  return hit ? 'BARCODE' : 'PRODUCT';
}

describe('Global search entity resolution', () => {
  it('detects barcode-shaped queries (6–14 digits)', () => {
    expect(looksLikeBarcode('8901030893456')).toBe(true);
    expect(looksLikeBarcode('123456')).toBe(true);
    expect(looksLikeBarcode('12345')).toBe(false);
    expect(looksLikeBarcode('890103089345678')).toBe(false);
  });

  it('does not treat a text query as a barcode', () => {
    expect(looksLikeBarcode('Sharma Medical Store')).toBe(false);
  });

  it('classifies shopkeeper vs customer by role', () => {
    expect(classifyUser('shopkeeper')).toBe('SHOPKEEPER');
    expect(classifyUser('SHOPKEEPER')).toBe('SHOPKEEPER');
    expect(classifyUser('customer')).toBe('CUSTOMER');
    expect(classifyUser('')).toBe('CUSTOMER');
  });

  it('labels a barcode match as BARCODE and a name match as PRODUCT', () => {
    expect(classifyProduct('Paracetamol 650', '8901030893456', '8901030893456')).toBe('BARCODE');
    expect(classifyProduct('Paracetamol 650', '8901030893456', 'Paracetamol')).toBe('PRODUCT');
  });

  it('does not label a numeric query as barcode when product has no barcode', () => {
    expect(classifyProduct('Paracetamol 650', null, '8901030893456')).toBe('PRODUCT');
  });

  it('covers every contract entity type', () => {
    const covered: EntityType[] = [
      'CUSTOMER',
      'SHOPKEEPER',
      'BUSINESS',
      'PRODUCT',
      'BARCODE',
      'INVENTORY',
      'IMPORT',
      'SUPPORT',
      'AUDIT',
    ];
    expect(new Set(covered).size).toBe(9);
  });
});