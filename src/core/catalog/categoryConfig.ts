import type { CategoryConfigDraft, CategoryItem } from '../types/admin';

/**
 * Category configuration — the frontend half of the "CATEGORY CONFIGURATION"
 * spec section.
 *
 * Design rule (from the spec): "Do not implement category rules only in the
 * frontend." These helpers therefore do not *decide* anything. They:
 *
 *   1. Mirror the backend's normalisation exactly, so the value the console
 *      shows after a save is the value the server stored (no phantom diffs).
 *   2. Compute the minimal, partial PATCH body — only fields the operator
 *      actually changed are sent, so an edit to the description can never
 *      silently rewrite the field template.
 *   3. Produce operator-facing validation *before* a request, purely to avoid a
 *      round-trip for an obviously empty name. The server remains the authority
 *      and its 4xx is still surfaced verbatim.
 *
 * The identifier normalisation is intentionally identical to the backend's
 * `_normalise_identifier_list` (`catalog.py`): lowercase, spaces/hyphens to
 * underscores, drop blanks, de-duplicate, reject anything outside
 * `^[a-z0-9_]{1,64}$`.
 */

export const CATEGORY_IDENTIFIER_PATTERN = /^[a-z0-9_]{1,64}$/;

/**
 * Normalise a free-text field list (comma- or newline-separated) into the
 * canonical identifier list the backend stores. Blanks are dropped so a trailing
 * comma does not produce a phantom entry.
 */
export function parseFieldList(text: string): string[] {
  const out: string[] = [];
  splitTokens(text).forEach((raw) => {
    const token = normaliseIdentifier(raw);
    if (token && !out.includes(token)) out.push(token);
  });
  return out;
}

/** Split on commas and newlines, trim, drop empties. */
export function splitTokens(text: string): string[] {
  return (text || '')
    .split(/[,\n]/)
    .map((part) => part.trim())
    .filter(Boolean);
}

/**
 * Normalise one identifier the same way the server does. Returns `null` for an
 * empty token so callers can filter it out.
 */
export function normaliseIdentifier(raw: string): string | null {
  const token = (raw || '').trim().toLowerCase().replace(/\s+/g, '_').replace(/-/g, '_');
  return token || null;
}

/** Identifiers in `text` that are well-formed and unique. */
export function validFieldList(text: string): { values: string[]; invalid: string[] } {
  const values: string[] = [];
  const invalid: string[] = [];
  splitTokens(text).forEach((raw) => {
    const token = normaliseIdentifier(raw);
    if (!token) return;
    if (!CATEGORY_IDENTIFIER_PATTERN.test(token)) {
      invalid.push(raw);
      return;
    }
    if (!values.includes(token)) values.push(token);
  });
  return { values, invalid };
}

/** Exact array equality, order-sensitive (the server preserves order). */
export function sameList(a: string[] | null | undefined, b: string[] | null | undefined): boolean {
  const left = a || [];
  const right = b || [];
  return left.length === right.length && left.every((v, i) => v === right[i]);
}

/** The editable draft for a row, or a blank draft for a create. */
export function draftFromCategory(item?: CategoryItem | null): CategoryConfigDraft {
  return {
    name: item?.name ?? '',
    slug: item?.slug ?? '',
    description: item?.description ?? '',
    status: item?.is_active === false ? 'INACTIVE' : 'ACTIVE',
    sortOrder: String(item?.sort_order ?? 0),
    parentId: item?.parent_id == null ? '' : String(item.parent_id),
    requiredFields: (item?.required_fields || []).join(', '),
    optionalFields: (item?.optional_fields || []).join(', '),
    featureCapabilities: [...(item?.feature_capabilities || [])],
  };
}

/** Slugify a name into a URL-safe token, for the create dialog's helper. */
export function slugify(name: string): string {
  return (name || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

export interface CategoryConfigValidation {
  ok: boolean;
  /** Per-field messages, keyed by draft field name. */
  errors: Partial<Record<keyof CategoryConfigDraft, string>>;
}

/**
 * Pre-flight validation to avoid a needless round-trip. The backend re-checks
 * every one of these; nothing here grants a capability the server would refuse.
 */
export function validateDraft(draft: CategoryConfigDraft, mode: 'create' | 'edit'): CategoryConfigValidation {
  const errors: CategoryConfigValidation['errors'] = {};
  if (!draft.name.trim()) errors.name = 'Name is required.';
  if (mode === 'create' && !draft.slug.trim()) errors.slug = 'Slug is required.';

  const required = validFieldList(draft.requiredFields);
  const optional = validFieldList(draft.optionalFields);
  if (required.invalid.length) {
    errors.requiredFields = `Invalid identifier(s): ${required.invalid.join(', ')}. Use letters, digits, underscores.`;
  }
  if (optional.invalid.length) {
    errors.optionalFields = `Invalid identifier(s): ${optional.invalid.join(', ')}. Use letters, digits, underscores.`;
  }

  const so = Number(draft.sortOrder);
  if (draft.sortOrder !== '' && !Number.isFinite(so)) {
    errors.sortOrder = 'Sort order must be a whole number.';
  } else if (Number.isFinite(so) && !Number.isInteger(so)) {
    errors.sortOrder = 'Sort order must be a whole number.';
  }

  return { ok: Object.keys(errors).length === 0, errors };
}

/**
 * Build the partial PATCH body: only the fields whose value actually changed,
 * plus the derived `is_subcategory` when the parent moved.
 *
 * Why partial: the spec's configuration surface is large, and sending the whole
 * record on every edit means two operators editing different fields race and one
 * silently clobbers the other. Sending only the diff also keeps the audit log's
 * `details.fields` list meaningful — it names what really changed.
 *
 * An explicitly emptied list is sent as `[]` (an intentional clear), never
 * omitted, so clearing a template is possible and is recorded as a change.
 */
export function toCategoryConfigBody(
  draft: CategoryConfigDraft,
  original?: CategoryItem | null,
  mode: 'create' | 'edit' = 'edit'
): Record<string, unknown> {
  const required = validFieldList(draft.requiredFields).values;
  const optional = validFieldList(draft.optionalFields).values;
  const nextParent = draft.parentId.trim() === '' ? null : Number(draft.parentId);
  const nextSort = draft.sortOrder === '' ? 0 : Number(draft.sortOrder);
  const nextActive = draft.status !== 'INACTIVE';

  if (mode === 'create' || !original) {
    const body: Record<string, unknown> = {
      name: draft.name.trim(),
      slug: draft.slug.trim() || slugify(draft.name),
      description: draft.description.trim() || null,
      sort_order: Number.isFinite(nextSort) ? nextSort : 0,
      is_active: nextActive,
      required_fields: required,
      optional_fields: optional,
      feature_capabilities: [...draft.featureCapabilities],
    };
    if (nextParent !== null && Number.isFinite(nextParent)) {
      body.parent_id = nextParent;
    }
    return body;
  }

  const body: Record<string, unknown> = {};
  if (draft.name.trim() !== original.name) body.name = draft.name.trim();
  if (draft.slug.trim() && draft.slug.trim() !== original.slug) body.slug = draft.slug.trim();
  if (draft.description.trim() !== (original.description || '')) {
    body.description = draft.description.trim();
  }

  const originalActive = original.is_active !== false;
  if (nextActive !== originalActive) body.is_active = nextActive;

  const originalSort = Number(original.sort_order ?? 0);
  if (Number.isFinite(nextSort) && nextSort !== originalSort) body.sort_order = nextSort;

  const originalParent = original.parent_id == null ? null : Number(original.parent_id);
  if (nextParent !== originalParent) {
    body.parent_id = nextParent;
    // Derived server-side too, but sent so the response the frontend already
    // holds agrees with the server without a refetch race.
    body.is_subcategory = nextParent !== null;
  }

  if (!sameList(required, original.required_fields)) body.required_fields = required;
  if (!sameList(optional, original.optional_fields)) body.optional_fields = optional;
  if (!sameList(draft.featureCapabilities, original.feature_capabilities)) {
    body.feature_capabilities = [...draft.featureCapabilities];
  }

  return body;
}

/** Human summary of a category's configuration, for a table cell tooltip. */
export function describeCategoryConfig(item: CategoryItem): string {
  const parts: string[] = [];
  if (item.required_fields?.length) parts.push(`Required: ${item.required_fields.join(', ')}`);
  if (item.optional_fields?.length) parts.push(`Optional: ${item.optional_fields.join(', ')}`);
  if (item.feature_capabilities?.length) parts.push(`Features: ${item.feature_capabilities.join(', ')}`);
  return parts.length ? parts.join(' · ') : 'No listing template configured.';
}
