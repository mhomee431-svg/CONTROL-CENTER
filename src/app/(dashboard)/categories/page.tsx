'use client';

import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import {
  Box,
  Typography,
  Button,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  Alert,
} from '@mui/material';
import { Layers, Plus, Trash2 } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { CategoryItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';

export default function CategoriesPage() {
  const queryClient = useQueryClient();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 50 });

  // Dialog State
  const [openCreate, setOpenCreate] = useState(false);
  const [name, setName] = useState('');
  const [slug, setSlug] = useState('');
  const [description, setDescription] = useState('');
  const [createError, setCreateError] = useState<string | null>(null);

  // Delete State
  const [deleteTarget, setDeleteTarget] = useState<CategoryItem | null>(null);

  const { data, isLoading, isError, refetch } = useQuery<{ items: CategoryItem[] }>({
    queryKey: ['admin', 'categories'],
    queryFn: () => apiClient<{ items: CategoryItem[] }>(API_ENDPOINTS.CATEGORIES.LIST),
  });

  const createMutation = useMutation({
    mutationFn: (newCat: { name: string; slug: string; description?: string }) =>
      apiClient(API_ENDPOINTS.CATEGORIES.CREATE, {
        method: 'POST',
        body: JSON.stringify({ ...newCat, is_active: true, sort_order: 0 }),
      }),
    onSuccess: () => {
      setOpenCreate(false);
      setName('');
      setSlug('');
      setDescription('');
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

  const handleCreateSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim() || !slug.trim()) {
      setCreateError('Name and Slug are required.');
      return;
    }
    // Section 33 rule: Do NOT add Grocery or General Food
    if (name.toLowerCase().includes('grocery') || name.toLowerCase().includes('general food')) {
      setCreateError('Rule Violation: Section 33 explicitly forbids adding Grocery or General Food categories.');
      return;
    }
    setCreateError(null);
    try {
      await createMutation.mutateAsync({ name, slug, description });
    } catch (err: unknown) {
      setCreateError(err instanceof Error ? err.message : 'Failed to create category');
    }
  };

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    {
      field: 'name',
      headerName: 'Category Name',
      flex: 1.5,
      minWidth: 200,
      renderCell: (params) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <Layers size={16} color="#0F52BA" />
          <Typography variant="body2" sx={{ fontWeight: 600 }}>
            {params.value as string}
          </Typography>
        </Box>
      ),
    },
    { field: 'slug', headerName: 'Slug', flex: 1, minWidth: 140 },
    { field: 'description', headerName: 'Description', flex: 1.5, minWidth: 200 },
    {
      field: 'is_active',
      headerName: 'Status',
      width: 120,
      renderCell: (params) => <StatusBadge status={params.value ? 'ACTIVE' : 'INACTIVE'} />,
    },
    {
      field: 'actions',
      headerName: 'Actions',
      width: 120,
      sortable: false,
      renderCell: (params) => {
        const item = params.row as CategoryItem;
        return (
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
        );
      },
    },
  ];

  return (
    <Box>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
        <Box>
          <Typography variant="h5" sx={{ fontWeight: 700 }}>
            Category Taxonomy Management
          </Typography>
          <Typography variant="body2" color="text.secondary">
            Section 33: Regulated platform taxonomy. Discovery-based category hierarchy.
          </Typography>
        </Box>

        <PermissionGuard capability={CAPABILITIES.TAXONOMY_MANAGE}>
          <Button
            variant="contained"
            startIcon={<Plus size={16} />}
            onClick={() => setOpenCreate(true)}
          >
            Add Category
          </Button>
        </PermissionGuard>
      </Box>

      <AdminDataGrid
        rows={(data?.items || []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.items?.length ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        onRefresh={() => refetch()}
        error={isError}
      />

      {/* Create Dialog */}
      <Dialog open={openCreate} onClose={() => setOpenCreate(false)} maxWidth="sm" fullWidth>
        <DialogTitle sx={{ fontWeight: 600 }}>Add Platform Category</DialogTitle>
        <Box component="form" onSubmit={handleCreateSubmit}>
          <DialogContent>
            {createError && (
              <Alert severity="error" sx={{ mb: 2 }}>
                {createError}
              </Alert>
            )}
            <TextField
              margin="dense"
              label="Category Name"
              fullWidth
              required
              value={name}
              onChange={(e) => {
                setName(e.target.value);
                if (!slug) setSlug(e.target.value.toLowerCase().replace(/\s+/g, '-'));
              }}
            />
            <TextField
              margin="dense"
              label="URL Slug"
              fullWidth
              required
              value={slug}
              onChange={(e) => setSlug(e.target.value)}
            />
            <TextField
              margin="dense"
              label="Description"
              fullWidth
              multiline
              rows={2}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
          </DialogContent>
          <DialogActions sx={{ px: 3, pb: 2 }}>
            <Button onClick={() => setOpenCreate(false)} color="inherit">
              Cancel
            </Button>
            <Button type="submit" variant="contained" disabled={createMutation.isPending}>
              {createMutation.isPending ? 'Creating...' : 'Create Category'}
            </Button>
          </DialogActions>
        </Box>
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
