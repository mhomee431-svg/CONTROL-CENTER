'use client';

import React from 'react';
import { useRouter } from 'next/navigation';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  Alert,
  Box,
  Button,
  Card,
  CardContent,
  Chip,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  Divider,
  Grid,
  Typography,
} from '@mui/material';
import { ArrowLeft, Edit3, Layers } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { CategoryConfigDraft, CategoryItem } from '@/core/types/admin';
import { draftFromCategory, toCategoryConfigBody, validateDraft } from '@/core/catalog/categoryConfig';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';
import { ROUTES } from '@/core/routes/routes';
import { CategoryConfigForm, CategoryConfigSkeleton } from '../CategoryConfigForm';

/**
 * Category drill-down: the full configuration of one taxonomy node.
 *
 * Reads the dedicated `GET /admin/categories/{id}` route rather than borrowing
 * the list, so the surface says "this deployment has not published the route"
 * (a 404/405) distinctly from "this category does not exist".
 */
export default function CategoryDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = React.use(params);
  const router = useRouter();
  const queryClient = useQueryClient();

  const [editOpen, setEditOpen] = React.useState(false);
  const [draft, setDraft] = React.useState<CategoryConfigDraft | null>(null);
  const [editError, setEditError] = React.useState<string | null>(null);

  const { data: category, isLoading, isError } = useQuery<CategoryItem>({
    queryKey: ['admin', 'category', String(id)],
    queryFn: () => apiClient<CategoryItem>(API_ENDPOINTS.CATEGORIES.DETAIL(id)),
  });

  // All categories, for the parent picker.
  const { data: allCategories } = useQuery<{ items: CategoryItem[] }>({
    queryKey: ['admin', 'categories', 'all'],
    queryFn: () =>
      apiClient<{ items: CategoryItem[] }>(API_ENDPOINTS.CATEGORIES.LIST, {
        params: { page_size: 500 },
      }),
  });

  const parent = React.useMemo(() => {
    if (category?.parent_id == null) return null;
    return (
      (allCategories?.items || []).find((c) => c.id === Number(category.parent_id)) ?? null
    );
  }, [category, allCategories]);

  const updateMutation = useMutation({
    mutationFn: (body: Record<string, unknown>) =>
      apiClient(API_ENDPOINTS.CATEGORIES.UPDATE(id), {
        method: 'PATCH',
        body: JSON.stringify(body),
      }),
    onSuccess: () => {
      setEditOpen(false);
      setDraft(null);
      setEditError(null);
      queryClient.invalidateQueries({ queryKey: ['admin', 'category', String(id)] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'categories'] });
    },
  });

  const openEdit = () => {
    if (!category) return;
    setDraft(draftFromCategory(category));
    setEditError(null);
    setEditOpen(true);
  };

  const submitEdit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!draft || !category) return;
    if (!validateDraft(draft, 'edit').ok) return;
    const body = toCategoryConfigBody(draft, category, 'edit');
    if (Object.keys(body).length === 0) {
      setEditOpen(false);
      setDraft(null);
      return;
    }
    setEditError(null);
    try {
      await updateMutation.mutateAsync(body);
    } catch (err: unknown) {
      setEditError(err instanceof Error ? err.message : 'Failed to update category');
    }
  };

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Categories', href: ROUTES.CATEGORIES },
          { label: category?.name || `Category #${id}` },
        ]}
      />
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
        <Button startIcon={<ArrowLeft size={16} />} onClick={() => router.push(ROUTES.CATEGORIES)}>
          Back to Categories
        </Button>
        {category && (
          <PermissionGuard capability={CAPABILITIES.TAXONOMY_MANAGE}>
            <Button variant="contained" startIcon={<Edit3 size={16} />} onClick={openEdit}>
              Configure
            </Button>
          </PermissionGuard>
        )}
      </Box>

      {isLoading && <CategoryConfigSkeleton />}
      {isError && <Alert severity="error">Could not load category #{id}.</Alert>}
      {!isLoading && !category && <Alert severity="warning">Category #{id} was not found in the taxonomy.</Alert>}

      {category && (
        <Card>
          <CardContent sx={{ p: 3 }}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                <Box sx={{ p: 1.2, borderRadius: 2, backgroundColor: '#EFF6FF', color: 'primary.main' }}>
                  <Layers size={24} />
                </Box>
                <Box>
                  <Typography variant="h6" sx={{ fontWeight: 700 }}>
                    {category.name}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    Slug: {category.slug}
                  </Typography>
                </Box>
              </Box>
              <StatusBadge status={category.is_active ? 'ACTIVE' : 'INACTIVE'} size="medium" />
            </Box>
            <Divider sx={{ my: 2 }} />
            <Grid container spacing={2}>
              <Grid item xs={12} sm={6}>
                <Typography variant="caption" color="text.secondary">
                  Description
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {category.description || 'No description provided'}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={3}>
                <Typography variant="caption" color="text.secondary">
                  Sort Order
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {category.sort_order}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={3}>
                <Typography variant="caption" color="text.secondary">
                  Classification
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {category.parent_id == null
                    ? 'Top-level category'
                    : `Subcategory of ${parent?.name ?? `#${category.parent_id}`}`}
                </Typography>
              </Grid>
            </Grid>

            <Divider sx={{ my: 2 }} />

            {/* Listing template — the configuration the spec calls out. */}
            <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 1 }}>
              Listing Template & Feature Capabilities
            </Typography>
            <Grid container spacing={2}>
              <Grid item xs={12} sm={4}>
                <Typography variant="caption" color="text.secondary">
                  Required fields
                </Typography>
                <ConfigChips
                  values={category.required_fields}
                  emptyLabel="No required fields"
                  color="error"
                />
              </Grid>
              <Grid item xs={12} sm={4}>
                <Typography variant="caption" color="text.secondary">
                  Optional fields
                </Typography>
                <ConfigChips values={category.optional_fields} emptyLabel="No optional fields" />
              </Grid>
              <Grid item xs={12} sm={4}>
                <Typography variant="caption" color="text.secondary">
                  Feature capabilities
                </Typography>
                <ConfigChips
                  values={category.feature_capabilities}
                  emptyLabel="No features enabled"
                  tone="feature"
                />
              </Grid>
            </Grid>
          </CardContent>
        </Card>
      )}

      {/* Configure Dialog — partial PATCH of only the changed fields. */}
      <Dialog
        open={editOpen}
        onClose={() => {
          setEditOpen(false);
          setDraft(null);
        }}
        maxWidth="md"
        fullWidth
      >
        <DialogTitle sx={{ fontWeight: 600 }}>Configure — {category?.name}</DialogTitle>
        {draft && (
          <Box component="form" onSubmit={submitEdit}>
            <DialogContent dividers>
              <CategoryConfigForm
                mode="edit"
                value={draft}
                onChange={setDraft}
                errors={validateDraft(draft, 'edit').errors}
                serverError={editError}
                categories={allCategories?.items || []}
                excludeId={category?.id ?? null}
              />
            </DialogContent>
            <DialogActions sx={{ px: 3, py: 2 }}>
              <Button
                onClick={() => {
                  setEditOpen(false);
                  setDraft(null);
                }}
                color="inherit"
              >
                Cancel
              </Button>
              <Button type="submit" variant="contained" disabled={updateMutation.isPending}>
                {updateMutation.isPending ? 'Saving…' : 'Save Changes'}
              </Button>
            </DialogActions>
          </Box>
        )}
      </Dialog>
    </Box>
  );
}

/** Renders a configuration list as chips, or an honest empty note. */
const ConfigChips: React.FC<{ values?: string[] | null; emptyLabel: string; color?: 'error'; tone?: 'feature' }> = ({
  values,
  emptyLabel,
  color,
  tone,
}) => {
  const list = values || [];
  if (list.length === 0) {
    return (
      <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
        {emptyLabel}
      </Typography>
    );
  }
  return (
    <Box sx={{ display: 'flex', gap: 0.5, flexWrap: 'wrap', mt: 0.5 }}>
      {list.map((v) => (
        <Chip
          key={v}
          label={v}
          size="small"
          color={color}
          variant={color ? 'outlined' : 'filled'}
          sx={tone === 'feature' ? { backgroundColor: '#EFF6FF', color: '#0F52BA' } : undefined}
        />
      ))}
    </Box>
  );
};
