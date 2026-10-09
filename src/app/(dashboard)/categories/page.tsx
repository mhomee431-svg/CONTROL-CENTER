'use client';

import React, { useMemo, useState } from 'react';
import Link from 'next/link';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import {
  Alert,
  Box,
  Button,
  Chip,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Tooltip,
  Typography,
} from '@mui/material';
import { Layers, Plus, Trash2, Edit3, Eye } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { CategoryConfigDraft, CategoryItem } from '@/core/types/admin';
import {
  describeCategoryConfig,
  draftFromCategory,
  toCategoryConfigBody,
  validateDraft,
} from '@/core/catalog/categoryConfig';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';
import { ROUTES } from '@/core/routes/routes';
import { CategoryConfigForm } from './CategoryConfigForm';

export default function CategoriesPage() {
  const queryClient = useQueryClient();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 50 });

  // Server-side search + a status chip filter. Search is a query param so a
  // large taxonomy is filtered by the backend; status is applied to the returned
  // page (the list route has no status param) so the chip stays honest.
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<'ALL' | 'ACTIVE' | 'INACTIVE'>('ALL');

  // Create state — a full CategoryConfigDraft, because a category is born with
  // its listing template rather than created blank and immediately edited.
  const [openCreate, setOpenCreate] = useState(false);
  const [createDraft, setCreateDraft] = useState<CategoryConfigDraft>(() => draftFromCategory(null));
  const [createError, setCreateError] = useState<string | null>(null);

  // Configure state. The dialog collects a draft; the partial PATCH body is
  // built by `toCategoryConfigBody`, so only changed fields are sent.
  const [editTarget, setEditTarget] = useState<CategoryItem | null>(null);
  const [editDraft, setEditDraft] = useState<CategoryConfigDraft | null>(null);
  const [editError, setEditError] = useState<string | null>(null);

  // Delete State
  const [deleteTarget, setDeleteTarget] = useState<CategoryItem | null>(null);

  const { data, isLoading, isError, refetch } = useQuery<{ items: CategoryItem[] }>({
    queryKey: ['admin', 'categories', { search }],
    queryFn: () =>
      apiClient<{ items: CategoryItem[] }>(API_ENDPOINTS.CATEGORIES.LIST, {
        params: { search: search || undefined },
      }),
  });

  // Unfiltered taxonomy, for the parent picker in both dialogs.
  const { data: allCategories } = useQuery<{ items: CategoryItem[] }>({
    queryKey: ['admin', 'categories', 'all'],
    queryFn: () =>
      apiClient<{ items: CategoryItem[] }>(API_ENDPOINTS.CATEGORIES.LIST, {
        params: { page_size: 500 },
      }),
  });

  const rows = useMemo(() => {
    const items = data?.items || [];
    if (statusFilter === 'ALL') return items;
    const wantActive = statusFilter === 'ACTIVE';
    return items.filter((c) => Boolean(c.is_active) === wantActive);
  }, [data, statusFilter]);

  const parentName = useMemo(() => {
    const map = new Map<number, string>();
    (allCategories?.items || []).forEach((c) => map.set(c.id, c.name));
    return (parentId?: number | null) =>
      parentId == null ? null : map.get(Number(parentId)) ?? `#${parentId}`;
  }, [allCategories]);

  const createMutation = useMutation({
    mutationFn: (body: Record<string, unknown>) =>
      apiClient(API_ENDPOINTS.CATEGORIES.CREATE, {
        method: 'POST',
        body: JSON.stringify(body),
      }),
    onSuccess: () => {
      setOpenCreate(false);
      setCreateDraft(draftFromCategory(null));
      setCreateError(null);
      queryClient.invalidateQueries({ queryKey: ['admin', 'categories'] });
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: number) =>
      apiClient(API_ENDPOINTS.CATEGORIES.DELETE(id), {
        method: 'DELETE',
      }),
    onSuccess: () => {
      setDeleteTarget(null);
      queryClient.invalidateQueries({ queryKey: ['admin', 'categories'] });
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, body }: { id: number; body: Record<string, unknown> }) =>
      apiClient(API_ENDPOINTS.CATEGORIES.UPDATE(id), {
        method: 'PATCH',
        body: JSON.stringify(body),
      }),
    onSuccess: () => {
      setEditTarget(null);
      setEditDraft(null);
      setEditError(null);
      queryClient.invalidateQueries({ queryKey: ['admin', 'categories'] });
    },
  });

  const openConfigure = (item: CategoryItem) => {
    setEditTarget(item);
    setEditDraft(draftFromCategory(item));
    setEditError(null);
  };

  const submitCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    const validation = validateDraft(createDraft, 'create');
    if (!validation.ok) return;
    setCreateError(null);
    try {
      await createMutation.mutateAsync(toCategoryConfigBody(createDraft, null, 'create'));
    } catch (err: unknown) {
      setCreateError(err instanceof Error ? err.message : 'Failed to create category');
    }
  };

  const submitEdit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editTarget || !editDraft) return;
    const validation = validateDraft(editDraft, 'edit');
    if (!validation.ok) return;
    const body = toCategoryConfigBody(editDraft, editTarget, 'edit');
    // Nothing changed: close without a request rather than firing a no-op PATCH
    // the backend answers with 422 "No fields to update".
    if (Object.keys(body).length === 0) {
      setEditTarget(null);
      setEditDraft(null);
      return;
    }
    setEditError(null);
    try {
      await updateMutation.mutateAsync({ id: editTarget.id, body });
    } catch (err: unknown) {
      setEditError(err instanceof Error ? err.message : 'Failed to update category');
    }
  };

  const STATUS_FILTERS: Array<{ value: 'ALL' | 'ACTIVE' | 'INACTIVE'; label: string }> = [
    { value: 'ALL', label: 'All' },
    { value: 'ACTIVE', label: 'Active' },
    { value: 'INACTIVE', label: 'Inactive' },
  ];
  const createValidation = validateDraft(createDraft, 'create');

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 70 },
    {
      field: 'name',
      headerName: 'Category',
      flex: 1.5,
      minWidth: 220,
      renderCell: (params) => {
        const item = params.row as CategoryItem;
        const parent = parentName(item.parent_id);
        return (
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            <Layers size={16} color="#0F52BA" />
            <Box sx={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
              <Typography variant="body2" sx={{ fontWeight: 600 }} noWrap>
                {item.name}
              </Typography>
              {parent && (
                <Typography variant="caption" color="text.secondary" noWrap>
                  Subcategory of {parent}
                </Typography>
              )}
            </Box>
          </Box>
        );
      },
    },
    { field: 'slug', headerName: 'Slug', flex: 1, minWidth: 140 },
    {
      field: 'description',
      headerName: 'Description',
      flex: 1.5,
      minWidth: 200,
      valueGetter: (value) => (value as string) || '—',
    },
    {
      field: 'is_active',
      headerName: 'Status',
      width: 120,
      renderCell: (params) => <StatusBadge status={params.value ? 'ACTIVE' : 'INACTIVE'} />,
    },
    {
      field: 'sort_order',
      headerName: 'Sort',
      width: 90,
      align: 'right',
      headerAlign: 'right',
      valueGetter: (value) => (value as number | null) ?? 0,
    },
    {
      // The listing template is the point of the configuration surface, so it
      // gets its own column rather than living only inside the dialog.
      field: 'config',
      headerName: 'Listing Template',
      flex: 1.6,
      minWidth: 240,
      sortable: false,
      renderCell: (params) => {
        const item = params.row as CategoryItem;
        const required = item.required_fields || [];
        const features = item.feature_capabilities || [];
        const hasConfig = required.length > 0 || (item.optional_fields || []).length > 0 || features.length > 0;
        return (
          <Tooltip title={describeCategoryConfig(item)}>
            <Box sx={{ display: 'flex', gap: 0.5, flexWrap: 'wrap', py: 0.5 }}>
              {required.slice(0, 2).map((f) => (
                <Chip key={`req-${f}`} label={f} size="small" color="error" variant="outlined" />
              ))}
              {required.length > 2 && (
                <Chip label={`+${required.length - 2}`} size="small" variant="outlined" />
              )}
              {features.slice(0, 2).map((f) => (
                <Chip
                  key={`feat-${f}`}
                  label={f}
                  size="small"
                  sx={{ backgroundColor: '#EFF6FF', color: '#0F52BA' }}
                />
              ))}
              {features.length > 2 && (
                <Chip
                  label={`+${features.length - 2}`}
                  size="small"
                  sx={{ backgroundColor: '#EFF6FF', color: '#0F52BA' }}
                />
              )}
              {!hasConfig && (
                <Typography variant="caption" color="text.secondary">
                  No template
                </Typography>
              )}
            </Box>
          </Tooltip>
        );
      },
    },
    {
      field: 'actions',
      headerName: 'Actions',
      width: 300,
      sortable: false,
      renderCell: (params) => {
        const item = params.row as CategoryItem;
        return (
          <Box sx={{ display: 'flex', gap: 0.5 }}>
            <Button
              size="small"
              component={Link}
              href={ROUTES.CATEGORY_DETAIL(item.id)}
              startIcon={<Eye size={14} />}
            >
              View
            </Button>
            <PermissionGuard capability={CAPABILITIES.TAXONOMY_MANAGE}>
              <Button size="small" startIcon={<Edit3 size={14} />} onClick={() => openConfigure(item)}>
                Configure
              </Button>
            </PermissionGuard>
            <PermissionGuard capability={CAPABILITIES.TAXONOMY_MANAGE}>
              <Button
                size="small"
                color="error"
                startIcon={<Trash2 size={14} />}
                onClick={() => setDeleteTarget(item)}
              >
                Delete
              </Button>
            </PermissionGuard>
          </Box>
        );
      },
    },
  ];

  return (
    <Box>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3, gap: 2 }}>
        <Box>
          <Typography variant="h5" sx={{ fontWeight: 700 }}>
            Category Configuration
          </Typography>
          <Typography variant="body2" color="text.secondary">
            Regulated platform taxonomy: identity, status, display order, the listing template
            (required / optional fields) and feature capabilities. Rules are enforced server-side.
          </Typography>
        </Box>

        <PermissionGuard capability={CAPABILITIES.TAXONOMY_MANAGE}>
          <Button
            variant="contained"
            startIcon={<Plus size={16} />}
            onClick={() => {
              setCreateDraft(draftFromCategory(null));
              setCreateError(null);
              setOpenCreate(true);
            }}
          >
            Add Category
          </Button>
        </PermissionGuard>
      </Box>

      <Box sx={{ display: 'flex', gap: 1, mb: 2, alignItems: 'center', flexWrap: 'wrap' }}>
        {STATUS_FILTERS.map((f) => (
          <Chip
            key={f.value}
            label={f.label}
            onClick={() => setStatusFilter(f.value)}
            color={statusFilter === f.value ? 'primary' : 'default'}
            variant={statusFilter === f.value ? 'filled' : 'outlined'}
            size="small"
          />
        ))}
        <Typography variant="caption" color="text.secondary" sx={{ ml: 'auto' }}>
          {rows.length} categor{rows.length === 1 ? 'y' : 'ies'}
        </Typography>
      </Box>

      <AdminDataGrid
        rows={rows as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={rows.length}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        searchPlaceholder="Search categories…"
        searchValue={search}
        onSearchChange={setSearch}
        onRefresh={() => refetch()}
        error={isError}
      />

      {/* Create Dialog — a category is born with its full configuration */}
      <Dialog open={openCreate} onClose={() => setOpenCreate(false)} maxWidth="md" fullWidth>
        <DialogTitle sx={{ fontWeight: 600 }}>Add Platform Category</DialogTitle>
        <Box component="form" onSubmit={submitCreate}>
          <DialogContent dividers>
            <CategoryConfigForm
              mode="create"
              value={createDraft}
              onChange={setCreateDraft}
              errors={createValidation.errors}
              serverError={createError}
              categories={allCategories?.items || []}
            />
          </DialogContent>
          <DialogActions sx={{ px: 3, py: 2 }}>
            <Button onClick={() => setOpenCreate(false)} color="inherit">
              Cancel
            </Button>
            <Button type="submit" variant="contained" disabled={createMutation.isPending}>
              {createMutation.isPending ? 'Creating…' : 'Create Category'}
            </Button>
          </DialogActions>
        </Box>
      </Dialog>

      {/* Configure Dialog — partial PATCH of only the changed fields */}
      <Dialog
        open={Boolean(editTarget)}
        onClose={() => {
          setEditTarget(null);
          setEditDraft(null);
        }}
        maxWidth="md"
        fullWidth
      >
        <DialogTitle sx={{ fontWeight: 600 }}>Configure — {editTarget?.name}</DialogTitle>
        {editDraft && (
          <Box component="form" onSubmit={submitEdit}>
            <DialogContent dividers>
              <CategoryConfigForm
                mode="edit"
                value={editDraft}
                onChange={setEditDraft}
                errors={validateDraft(editDraft, 'edit').errors}
                serverError={editError}
                categories={allCategories?.items || []}
                excludeId={editTarget?.id ?? null}
              />
            </DialogContent>
            <DialogActions sx={{ px: 3, py: 2 }}>
              <Button
                onClick={() => {
                  setEditTarget(null);
                  setEditDraft(null);
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

      {/* Delete Confirmation */}
      {deleteTarget && (
        <ConfirmationDialog
          open={Boolean(deleteTarget)}
          title={`Delete Category - ${deleteTarget.name}`}
          affectedItem={deleteTarget.name}
          consequence="Deleting a category may disconnect associated subcategories and product mappings."
          isDangerous
          requireReason
          isLoading={deleteMutation.isPending}
          onConfirm={async () => {
            await deleteMutation.mutateAsync(deleteTarget.id);
          }}
          onClose={() => setDeleteTarget(null)}
        />
      )}
    </Box>
  );
}
