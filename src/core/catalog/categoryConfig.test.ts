import { describe, it, expect } from 'vitest';
import {
  CATEGORY_IDENTIFIER_PATTERN,
  describeCategoryConfig,
  draftFromCategory,
  normaliseIdentifier,
  parseFieldList,
  sameList,
  slugify,
  toCategoryConfigBody,
  validateDraft,
} from '@/core/catalog/categoryConfig';
import type { CategoryConfigDraft, CategoryItem } from '@/core/types/admin';

/**
 * Locks down the CATEGORY CONFIGURATION spec section:
 *
 *   manage: name, description, status, sort order,
 *           required fields, optional fields, feature capabilities
 *
 *   "Do not implement category rules only in the frontend."
 *
 * These tests assert the *shape* of what the console sends — a partial PATCH of
 * only the changed fields, normalised exactly as the backend normalises — so no
 * rule is invented client-side and no unchanged field is clobbered.
 */

const category = (overrides: Partial<CategoryItem> = {}): CategoryItem => ({
  id: 1,
  name: 'Pharmacy & Healthcare',
  slug: 'pharmacy-healthcare',
  description: 'Medicines and health products',
  sort_order: 1,
  is_active: true,
  is_subcategory: false,
  required_fields: ['expiry_date'],
  optional_fields: ['batch_number'],
  feature_capabilities: ['delivery'],
  ...overrides,
});

const draft = (overrides: Partial<CategoryConfigDraft> = {}): CategoryConfigDraft => ({
  ...draftFromCategory(category()),
  ...overrides,
});

describe('identifier normalisation mirrors the backend', () => {
  it('lowercases, converts spaces/hyphens, and drops blanks', () => {
    expect(normaliseIdentifier('  Expiry Date ')).toBe('expiry_date');
    expect(normaliseIdentifier('shelf-life')).toBe('shelf_life');
    expect(normaliseIdentifier('   ')).toBeNull();
  });

  it('parses a comma-separated field list into unique identifiers', () => {
    expect(parseFieldList('Expiry Date, batch number , expiry_date')).toEqual([
      'expiry_date',
      'batch_number',
    ]);
  });

  it('accepts newline-separated input too', () => {
    expect(parseFieldList('size\nmaterial')).toEqual(['size', 'material']);
  });

  it('uses the same identifier pattern the backend enforces', () => {
    expect(CATEGORY_IDENTIFIER_PATTERN.test('expiry_date')).toBe(true);
    expect(CATEGORY_IDENTIFIER_PATTERN.test('Expiry')).toBe(false);
    expect(CATEGORY_IDENTIFIER_PATTERN.test('a'.repeat(65))).toBe(false);
    expect(CATEGORY_IDENTIFIER_PATTERN.test('')).toBe(false);
  });
});

describe('slugify', () => {
  it('produces a URL-safe slug', () => {
    expect(slugify('Beauty & Personal Care')).toBe('beauty-personal-care');
    expect(slugify('  Leading and trailing  ')).toBe('leading-and-trailing');
  });
});

describe('draftFromCategory', () => {
  it('carries every configurable field from the row', () => {
    const d = draftFromCategory(category({ parent_id: 7, is_active: false, sort_order: 4 }));
    expect(d.name).toBe('Pharmacy & Healthcare');
    expect(d.slug).toBe('pharmacy-healthcare');
    expect(d.description).toBe('Medicines and health products');
    expect(d.status).toBe('INACTIVE');
    expect(d.sortOrder).toBe('4');
    expect(d.parentId).toBe('7');
    expect(d.requiredFields).toBe('expiry_date');
    expect(d.optionalFields).toBe('batch_number');
    expect(d.featureCapabilities).toEqual(['delivery']);
  });

  it('produces a blank draft for a create', () => {
    const d = draftFromCategory(null);
    expect(d.name).toBe('');
    expect(d.status).toBe('ACTIVE');
    expect(d.sortOrder).toBe('0');
    expect(d.parentId).toBe('');
    expect(d.featureCapabilities).toEqual([]);
  });
});

describe('validateDraft — pre-flight only, server stays authoritative', () => {
  it('accepts a complete draft', () => {
    expect(validateDraft(draft(), 'edit').ok).toBe(true);
  });

  it('requires a name in both modes', () => {
    const result = validateDraft(draft({ name: '  ' }), 'create');
    expect(result.ok).toBe(false);
    expect(result.errors.name).toBeDefined();
  });

  it('requires a slug only on create', () => {
    expect(validateDraft(draft({ slug: '' }), 'create').errors.slug).toBeDefined();
    expect(validateDraft(draft({ slug: '' }), 'edit').errors.slug).toBeUndefined();
  });

  it('reports malformed field identifiers', () => {
    const result = validateDraft(draft({ requiredFields: 'expiry_date, bad field!' }), 'edit');
    // "bad field!" normalises to "bad_field!" which still fails the pattern.
    expect(result.errors.requiredFields).toBeDefined();
  });

  it('rejects a non-integer sort order', () => {
    expect(validateDraft(draft({ sortOrder: 'abc' }), 'edit').errors.sortOrder).toBeDefined();
    expect(validateDraft(draft({ sortOrder: '1.5' }), 'edit').errors.sortOrder).toBeDefined();
  });
});

describe('toCategoryConfigBody — create sends the full configuration', () => {
  it('includes name, description, status, sort order and the listing template', () => {
    const body = toCategoryConfigBody(
      draft({ name: 'Hardware', slug: 'hardware', description: 'Tools', requiredFields: 'material', optionalFields: '', featureCapabilities: ['delivery', 'warranty'] }),
      null,
      'create'
    );
    expect(body).toMatchObject({
      name: 'Hardware',
      slug: 'hardware',
      description: 'Tools',
      sort_order: 1,
      is_active: true,
      required_fields: ['material'],
      optional_fields: [],
      feature_capabilities: ['delivery', 'warranty'],
    });
  });

  it('includes parent_id only when a parent was chosen', () => {
    expect(toCategoryConfigBody(draft({ parentId: '' }), null, 'create').parent_id).toBeUndefined();
    expect(toCategoryConfigBody(draft({ parentId: '3' }), null, 'create').parent_id).toBe(3);
  });

  it('derives the slug from the name when the slug is blank', () => {
    const body = toCategoryConfigBody(draft({ name: 'Home Care', slug: '' }), null, 'create');
    expect(body.slug).toBe('home-care');
  });
});

describe('toCategoryConfigBody — edit sends only the changed fields', () => {
  it('sends an empty body when nothing changed', () => {
    const body = toCategoryConfigBody(draft(), category(), 'edit');
    expect(body).toEqual({});
  });

  it('sends only the description when only the description changed', () => {
    const body = toCategoryConfigBody(draft({ description: 'Updated copy' }), category(), 'edit');
    expect(body).toEqual({ description: 'Updated copy' });
  });

  it('sends status + sort order when they changed', () => {
    const body = toCategoryConfigBody(draft({ status: 'INACTIVE', sortOrder: '9' }), category(), 'edit');
    expect(body).toEqual({ is_active: false, sort_order: 9 });
  });

  it('sends the field template only when it changed', () => {
    const body = toCategoryConfigBody(draft({ requiredFields: 'expiry_date, batch_number' }), category(), 'edit');
    expect(body).toEqual({ required_fields: ['expiry_date', 'batch_number'] });
  });

  it('treats an emptied field list as an explicit clear', () => {
    const body = toCategoryConfigBody(draft({ optionalFields: '' }), category(), 'edit');
    expect(body).toEqual({ optional_fields: [] });
  });

  it('sends feature capabilities only when the set changed', () => {
    const body = toCategoryConfigBody(
      draft({ featureCapabilities: ['delivery', 'prescription_required'] }),
      category(),
      'edit'
    );
    expect(body).toEqual({ feature_capabilities: ['delivery', 'prescription_required'] });
  });

  it('normalises field identifiers before comparing, so whitespace is not a change', () => {
    const body = toCategoryConfigBody(draft({ requiredFields: '  expiry_date  ' }), category(), 'edit');
    expect(body).toEqual({});
  });

  it('sets parent_id and the derived is_subcategory when reparenting', () => {
    const body = toCategoryConfigBody(draft({ parentId: '5' }), category(), 'edit');
    expect(body).toEqual({ parent_id: 5, is_subcategory: true });
  });

  it('clears the subcategory flag when moving a child back to root', () => {
    const child = category({ parent_id: 5, is_subcategory: true });
    const body = toCategoryConfigBody(draftFromCategory(child), child, 'edit');
    expect(body).toEqual({});
    const moved = toCategoryConfigBody({ ...draftFromCategory(child), parentId: '' }, child, 'edit');
    expect(moved).toEqual({ parent_id: null, is_subcategory: false });
  });
});

describe('sameList', () => {
  it('is order-sensitive and null-safe', () => {
    expect(sameList(['a', 'b'], ['a', 'b'])).toBe(true);
    expect(sameList(['b', 'a'], ['a', 'b'])).toBe(false);
    expect(sameList(null, undefined)).toBe(true);
    expect(sameList([], null)).toBe(true);
    expect(sameList(['a'], null)).toBe(false);
  });
});

describe('describeCategoryConfig', () => {
  it('summarises a configured category', () => {
    const text = describeCategoryConfig(category());
    expect(text).toContain('Required: expiry_date');
    expect(text).toContain('Optional: batch_number');
    expect(text).toContain('Features: delivery');
  });

  it('reports an unconfigured template honestly', () => {
    const text = describeCategoryConfig(
      category({ required_fields: [], optional_fields: [], feature_capabilities: [] })
    );
    expect(text).toBe('No listing template configured.');
  });
});
