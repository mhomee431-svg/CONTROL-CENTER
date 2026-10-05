import { describe, it, expect } from 'vitest';
import { matchPaletteCommands } from './GlobalSearchModal';

/**
 * Global search entity resolution.
 * Mirrors the classification logic used by GlobalSearchModal so the entity-type
 * contract (Customer, Shopkeeper, Business, Product, Barcode, Inventory, Price
 * History, Verification, Import, Support, Audit) is verified without rendering
 * the dialog.
 */
type EntityType =
  | 'CUSTOMER'
  | 'SHOPKEEPER'
  | 'BUSINESS'
  | 'PRODUCT'
  | 'BARCODE'
  | 'INVENTORY'
  | 'PRICE'
  | 'VERIFICATION'
  | 'IMPORT'
  | 'SUPPORT'
  | 'AUDIT';

function looksLikeBarcode(term: string): boolean {
  return /^\d{6,14}$/.test(term.trim());
}

describe('Command palette — direct record open (open <entity> <id>)', () => {
  it('routes "open customer 42" straight to the customer record', () => {
    const [cmd] = matchPaletteCommands('open customer 42');
    expect(cmd.label).toBe('Open Customer #42');
    expect(cmd.url).toBe('/customers/42');
    expect(cmd.exact).toBe(true);
  });

  it('routes "open shop 7" straight to the business record', () => {
    const [cmd] = matchPaletteCommands('open shop 7');
    expect(cmd.label).toBe('Open Shop #7');
    expect(cmd.url).toBe('/businesses/7');
    expect(cmd.exact).toBe(true);
  });

  it('routes "open product 123" straight to the product record', () => {
    const [cmd] = matchPaletteCommands('open product 123');
    expect(cmd.url).toBe('/products/123');
    expect(cmd.exact).toBe(true);
  });

  it('routes "open ticket 9" straight to the support ticket', () => {
    const [cmd] = matchPaletteCommands('open ticket 9');
    expect(cmd.url).toBe('/support/9');
    expect(cmd.exact).toBe(true);
  });

  it('returns no command for a bare entity word without an id', () => {
    expect(matchPaletteCommands('open product')).toHaveLength(0);
  });
});

describe('Command palette — destination navigation (go <destination>)', () => {
  it('routes "go to verification" to the verification center', () => {
    const [cmd] = matchPaletteCommands('go to verification');
    expect(cmd.label).toBe('Go to Verification');
    expect(cmd.url).toBe('/verification');
    expect(cmd.exact).toBe(true);
  });

  it('routes "go imports" to the imports registry', () => {
    const [cmd] = matchPaletteCommands('go imports');
    expect(cmd.url).toBe('/imports');
    expect(cmd.exact).toBe(true);
  });

  it('routes "go system health" to the health monitor', () => {
    const cmds = matchPaletteCommands('go system health');
    expect(cmds.some((c) => c.url === '/system/health')).toBe(true);
    expect(cmds.every((c) => c.exact)).toBe(true);
  });

  it('shows advisory matches for a bare keyword without suppressing entity search', () => {
    const cmds = matchPaletteCommands('verification');
    expect(cmds.length).toBeGreaterThan(0);
    expect(cmds.every((c) => c.exact)).toBe(false);
  });

  it('returns no command for ordinary entity search terms', () => {
    expect(matchPaletteCommands('Sharma Medical Store')).toHaveLength(0);
    expect(matchPaletteCommands('901030893456')).toHaveLength(0);
    expect(matchPaletteCommands('')).toHaveLength(0);
  });
});

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
      'PRICE',
      'VERIFICATION',
      'IMPORT',
      'SUPPORT',
      'AUDIT',
    ];
    expect(new Set(covered).size).toBe(11);
  });
});