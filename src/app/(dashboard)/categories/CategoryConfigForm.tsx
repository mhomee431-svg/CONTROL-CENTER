'use client';

import React from 'react';
import {
  Alert,
  Autocomplete,
  Box,
  Chip,
  CircularProgress,
  Divider,
  MenuItem,
  TextField,
  Typography,
} from '@mui/material';
import { useQuery } from '@tanstack/react-query';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { CategoryConfigCatalog, CategoryConfigDraft, CategoryItem } from '@/core/types/admin';
import { CategoryConfigValidation, parseFieldList, slugify } from '@/core/catalog/categoryConfig';

/**
 * The reusable category-configuration form — the single UI surface for every
 * configurable attribute the spec names:
 *
 *   name · description · status · sort order ·
 *   required fields · optional fields · feature capabilities
 *   (plus parent/subcategory, because a taxonomy node needs a place in the tree)
 *
 * It is presentational. The backend owns normalisation, validation and the
 * Section 33 rules; this form renders those rules, it does not define them:
 *
 *   - Feature capabilities are chosen from the server's `config-catalog`
 *     vocabulary, not a hardcoded list.
 *   - Field presets are offered from the same catalog as one-click suggestions,
 *     but any well-formed snake_case identifier is accepted (the API validates
 *     the final set).
 *   - The server's 4xx message is displayed verbatim, never rewritten.
 */

/**
 * Fallback vocabulary, used only while the catalog request is in flight or if a
 * deployment has not published the route. It mirrors the backend catalog so the
 * picker is never empty; the backend still validates the submitted set.
 */
const FALLBACK_FEATURES: CategoryConfigCatalog['feature_capabilities'] = [
  { key: 'delivery', label: 'Delivery' },
  { key: 'pickup', label: 'Pickup' },
  { key: 'installation', label: 'Installation' },
  { key: 'prescription_required', label: 'Prescription required' },
  { key: 'barcode_scan', label: 'Barcode scan' },
  { key: 'warranty', label: 'Warranty' },
  { key: 'serial_tracking', label: 'Serial tracking' },
  { key: 'age_restricted', label: 'Age restricted' },
  { key: 'bulk_pricing', label: 'Bulk pricing' },
  { key: 'custom_order', label: 'Custom order' },
];

export interface CategoryConfigFormProps {
  /** The draft the parent owns; the form reports changes upward. */
  value: CategoryConfigDraft;
  onChange: (next: CategoryConfigDraft) => void;
  mode: 'create' | 'edit';
  /** Field-level pre-flight errors from `validateDraft`. */
  errors?: CategoryConfigValidation['errors'];
  /** Server-reported error, shown verbatim above the fields. */
  serverError?: string | null;
  /** All categories, for the parent picker. */
  categories?: CategoryItem[];
  /** The record being edited, so it is excluded from its own parent list. */
  excludeId?: number | null;
}

export const CategoryConfigForm: React.FC<CategoryConfigFormProps> = ({
  value,
  onChange,
  mode,
  errors = {},
  serverError = null,
  categories = [],
  excludeId = null,
}) => {
  const { data: catalog } = useQuery<CategoryConfigCatalog>({
    queryKey: ['admin', 'category-config-catalog'],
    queryFn: () => apiClient<CategoryConfigCatalog>(API_ENDPOINTS.CATEGORIES.CONFIG_CATALOG),
    // The vocabulary is deployment configuration, not live data.
    staleTime: 5 * 60 * 1000,
  });

  const featureOptions = catalog?.feature_capabilities?.length
    ? catalog.feature_capabilities
    : FALLBACK_FEATURES;
  const fieldPresets = catalog?.field_presets || [];

  const set = <K extends keyof CategoryConfigDraft>(key: K, next: CategoryConfigDraft[K]) =>
    onChange({ ...value, [key]: next });

  // A category cannot parent itself, nor one of its own descendants. Descendants
  // are computed here only to keep the picker honest; the backend rejects a
  // self-parent outright.
  const descendantIds = React.useMemo(() => {
    if (excludeId == null) return new Set<number>();
    const childrenOf = new Map<number, number[]>();
    categories.forEach((c) => {
      if (c.parent_id == null) return;
      const list = childrenOf.get(Number(c.parent_id)) || [];
      list.push(c.id);
      childrenOf.set(Number(c.parent_id), list);
    });
    const out = new Set<number>();
    const walk = (id: number) => {
      (childrenOf.get(id) || []).forEach((child) => {
        if (out.has(child)) return;
        out.add(child);
        walk(child);
      });
    };
    walk(excludeId);
    return out;
  }, [categories, excludeId]);

  const parentOptions = categories.filter(
    (c) => c.id !== excludeId && !descendantIds.has(c.id)
  );

  const labelOf = (key: string) => featureOptions.find((f) => f.key === key)?.label || key;

  return (
    <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, pt: 1 }}>
      {serverError && <Alert severity="error">{serverError}</Alert>}

      <TextField
        label="Category Name"
        fullWidth
        required
        value={value.name}
        error={Boolean(errors.name)}
        helperText={errors.name || 'Shown to merchants and shoppers in every category picker.'}
        onChange={(e) => {
          const nextName = e.target.value;
          // In create mode, keep the slug in step while the operator types —
          // but only until they edit the slug themselves.
          const shouldSyncSlug = mode === 'create' && (!value.slug || value.slug === slugify(value.name));
          onChange({
            ...value,
            name: nextName,
            slug: shouldSyncSlug ? slugify(nextName) : value.slug,
          });
        }}
      />

      <TextField
        label="URL Slug"
        fullWidth
        required={mode === 'create'}
        value={value.slug}
        error={Boolean(errors.slug)}
        helperText={errors.slug || 'Stable identifier used in links and imports.'}
        onChange={(e) => set('slug', e.target.value)}
      />

      <TextField
        label="Description"
        fullWidth
        multiline
        rows={2}
        value={value.description}
        onChange={(e) => set('description', e.target.value)}
      />

      <Box sx={{ display: 'flex', gap: 2, flexWrap: 'wrap' }}>
        <TextField
          label="Status"
          select
          sx={{ flex: 1, minWidth: 220 }}
          value={value.status}
          onChange={(e) => set('status', e.target.value)}
          helperText="Inactive categories are hidden from shopper discovery."
        >
          <MenuItem value="ACTIVE">Active — listed in discovery</MenuItem>
          <MenuItem value="INACTIVE">Inactive — hidden from discovery</MenuItem>
        </TextField>

        <TextField
          label="Sort Order"
          type="number"
          sx={{ flex: 1, minWidth: 160 }}
          value={value.sortOrder}
          error={Boolean(errors.sortOrder)}
          helperText={errors.sortOrder || 'Lower numbers appear first.'}
          onChange={(e) => set('sortOrder', e.target.value)}
        />
      </Box>

      <TextField
        label="Parent Category"
        select
        fullWidth
        value={value.parentId}
        onChange={(e) => set('parentId', e.target.value)}
        helperText="Leave as “None” for a top-level category. Choosing a parent makes this a subcategory."
      >
        <MenuItem value="">None — top-level category</MenuItem>
        {parentOptions.map((c) => (
          <MenuItem key={c.id} value={String(c.id)}>
            {c.name}
          </MenuItem>
        ))}
      </TextField>

      <Divider sx={{ my: 0.5 }} />

      <Box>
        <Typography variant="subtitle2" sx={{ fontWeight: 700 }}>
          Listing template
        </Typography>
        <Typography variant="caption" color="text.secondary">
          The attributes merchants must and may provide for products in this category. Identifiers
          are saved in lowercase snake_case; the backend validates the final set.
        </Typography>
      </Box>

      <FieldListInput
        label="Required Fields"
        value={value.requiredFields}
        error={errors.requiredFields}
        presets={fieldPresets}
        helperText="Every merchant listing in this category must provide these (e.g. expiry_date, fssai_license)."
        onChange={(next) => set('requiredFields', next)}
      />

      <FieldListInput
        label="Optional Fields"
        value={value.optionalFields}
        error={errors.optionalFields}
        presets={fieldPresets}
        helperText="Merchants may provide these (e.g. brand, material)."
        onChange={(next) => set('optionalFields', next)}
      />

      <Box>
        <Autocomplete
          multiple
          options={featureOptions.map((f) => f.key)}
          value={value.featureCapabilities}
          onChange={(_, next) => set('featureCapabilities', next)}
          getOptionLabel={labelOf}
          renderTags={(selected, getTagProps) =>
            selected.map((key, index) => (
              <Chip
                {...getTagProps({ index })}
                key={key}
                label={labelOf(key)}
                size="small"
                sx={{ backgroundColor: '#EFF6FF', color: '#0F52BA' }}
              />
            ))
          }
          renderInput={(params) => (
            <TextField
              {...params}
              label="Feature Capabilities"
              placeholder="Add a capability…"
              helperText="Platform features switched on for this category (delivery, pickup, installation, …)."
            />
          )}
        />
      </Box>
    </Box>
  );
};

/**
 * A field-identifier input: free text with a preset picker. Keeping it free text
 * (rather than a strict select) means an operator can introduce a new merchant
 * attribute without a backend release, while the API still rejects malformed
 * identifiers — the rule stays on the server.
 */
const FieldListInput: React.FC<{
  label: string;
  value: string;
  onChange: (next: string) => void;
  helperText?: string;
  error?: string;
  presets: CategoryConfigCatalog['field_presets'];
}> = ({ label, value, onChange, helperText, error, presets }) => {
  const [preset, setPreset] = React.useState<string | null>(null);
  const tokens = parseFieldList(value);

  const addPreset = (key: string | null) => {
    setPreset(null);
    const token = (key || '').trim();
    if (!token || tokens.includes(token)) return;
    onChange([...tokens, token].join(', '));
  };

  return (
    <Box>
      <Box sx={{ display: 'flex', gap: 2, alignItems: 'flex-start' }}>
        <TextField
          label={label}
          fullWidth
          value={value}
          error={Boolean(error)}
          helperText={error || helperText}
          onChange={(e) => onChange(e.target.value)}
        />
        {presets.length > 0 && (
          <TextField
            select
            label="Add preset"
            value={preset ?? ''}
            onChange={(e) => addPreset(e.target.value)}
            sx={{ minWidth: 180, flexShrink: 0 }}
          >
            <MenuItem value="">Select…</MenuItem>
            {presets.map((p) => (
              <MenuItem key={p.key} value={p.key} disabled={tokens.includes(p.key)}>
                {p.label}
              </MenuItem>
            ))}
          </TextField>
        )}
      </Box>
      {tokens.length > 0 && (
        <Box sx={{ display: 'flex', gap: 0.5, flexWrap: 'wrap', mt: 1 }}>
          {tokens.map((t) => (
            <Chip key={t} label={t} size="small" variant="outlined" />
          ))}
        </Box>
      )}
    </Box>
  );
};

/** Loading placeholder shown while a category detail is being fetched. */
export const CategoryConfigSkeleton: React.FC = () => (
  <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
    <CircularProgress />
  </Box>
);
