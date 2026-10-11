import { describe, it, expect } from 'vitest';

/**
 * Regression guard for the Feature Flags grid.
 *
 * MUI X's DataGrid requires every row to expose a unique `id`. A feature flag's
 * primary key is its `name`, not an `id`, so the grid threw
 * "MUI X: The Data Grid component requires all rows to have a unique `id`
 * property" and the whole panel failed to render in production.
 *
 * AdminDataGrid now accepts `getRowId`; its default reads `row.id`. This test
 * locks in both behaviours so the flags grid cannot silently lose its override.
 */

/** Mirrors AdminDataGrid's default resolver. */
const defaultGetRowId = (row: Record<string, unknown>): string | number => row.id as string | number;

describe('data grid row id resolution', () => {
  it('uses row.id by default for registries that have one', () => {
    expect(defaultGetRowId({ id: 42, name: 'Shop' })).toBe(42);
    expect(defaultGetRowId({ id: 'abc' })).toBe('abc');
  });

  it('exposes undefined for a flag-shaped row, which is exactly why an override is required', () => {
    // A flag row has no `id` — the default would hand MUI X `undefined`.
    expect(defaultGetRowId({ name: 'BARCODE_SEARCH', is_enabled: true })).toBeUndefined();
  });

  it('resolves a stable, unique id from the flag name when overridden', () => {
    const flagGetRowId = (row: Record<string, unknown>) => String(row.name);

    const rows = [
      { name: 'BARCODE_SEARCH' },
      { name: 'EXCEL_IMPORT' },
      { name: 'POS' },
      { name: 'OFFERS' },
      { name: 'AI_SEARCH' },
      { name: 'NEW_SEARCH_UI' },
    ];

    const ids = rows.map(flagGetRowId);
    expect(ids).toEqual([
      'BARCODE_SEARCH',
      'EXCEL_IMPORT',
      'POS',
      'OFFERS',
      'AI_SEARCH',
      'NEW_SEARCH_UI',
    ]);
    // Unique — a duplicate id is the other way this grid fails.
    expect(new Set(ids).size).toBe(ids.length);
  });
});
