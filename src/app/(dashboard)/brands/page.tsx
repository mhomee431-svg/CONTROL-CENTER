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
import { Tag, Plus, Trash2 } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { BrandItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';
import { toCsv, downloadCsv } from '@/core/export/csv';

export default function BrandsPage() {
  const queryClient = useQueryClient();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 50 });

  const [openCreate, setOpenCreate] = useState(false);
  const [name, setName] = useState('');
  const [slug, setSlug] = useState('');
  const [description, setDescription] = useState('');
  const [createError, setCreateError] = useState<string | null>(null);

  const [deleteTarget, setDeleteTarget] = useState<BrandItem | null>(null);

  const { data, isLoading, isError, refetch } = useQuery<{ items: BrandItem[] }>({
    queryKey: ['admin', 'brands'],
    queryFn: () => apiClient<{ items: BrandItem[] }>(API_ENDPOINTS.BRANDS.LIST),
  });

  const createMutation = useMutation({
    mutationFn: (newBrand: { name: string; slug: string; description?: string }) =>
      apiClient(API_ENDPOINTS.BRANDS.CREATE, {
        method: 'POST',
        body: JSON.stringify({ ...newBrand, is_active: true }),
      }),
    onSuccess: () => {
      setOpenCreate(false);
      setName('');
      setSlug('');
      setDescription('');
      queryClient.invalidateQueries({ queryKey: ['admin', 'brands'] });
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: number) =>
      apiClient(API_ENDPOINTS.BRANDS.DELETE(id), {
        method: 'DELETE',
      }),
    onSuccess: () => {
      setDeleteTarget(null);
      queryClient.invalidateQueries({ queryKey: ['admin', 'brands'] });
    },
  });

  const handleCreateSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim() || !slug.trim()) {
      setCreateError('Brand Name and Slug are required.');
      return;
    }
    setCreateError(null);
    try {
      await createMutation.mutateAsync({ name, slug, description });
    } catch (err: unknown) {
      setCreateError(err instanceof Error ? err.message : 'Failed to create brand');
    }
  };

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    {
      field: 'name',
      headerName: 'Brand Name',
      flex: 1.5,
      minWidth: 180,
      renderCell: (params) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <Tag size={16} color="#0F52BA" />
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
        const item = params.row as BrandItem;
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
            Brand Registry
          </Typography>
          <Typography variant="body2" color="text.secondary">
            Section 35: Standardized master brands and brand mapping.
          </Typography>
        </Box>

        <PermissionGuard capability={CAPABILITIES.TAXONOMY_MANAGE}>
          <Button
            variant="contained"
            startIcon={<Plus size={16} />}
            onClick={() => setOpenCreate(true)}
          >
            Add Brand
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
        gridId="brands"
        showToolbar
        onExport={() =>
          downloadCsv(
            'brands.csv',
            toCsv(data?.items ?? [], [
              { header: 'ID', value: (b) => b.id },
              { header: 'Brand Name', value: (b) => b.name },
              { header: 'Slug', value: (b) => b.slug },
              { header: 'Description', value: (b) => b.description },
              { header: 'Active', value: (b) => (b.is_active ? 'ACTIVE' : 'INACTIVE') },
            ])
          )
        }
      />

      {/* Create Dialog */}
      <Dialog open={openCreate} onClose={() => setOpenCreate(false)} maxWidth="sm" fullWidth>
        <DialogTitle sx={{ fontWeight: 600 }}>Register New Brand</DialogTitle>
        <Box component="form" onSubmit={handleCreateSubmit}>
          <DialogContent>
            {createError && (
              <Alert severity="error" sx={{ mb: 2 }}>
                {createError}
              </Alert>
            )}
            <TextField
              margin="dense"
              label="Brand Name"
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
              {createMutation.isPending ? 'Saving...' : 'Save Brand'}
            </Button>
          </DialogActions>
        </Box>
      </Dialog>

      {/* Delete Confirmation */}
      {deleteTarget && (
        <ConfirmationDialog
          open={Boolean(deleteTarget)}
          title={`Delete Brand - ${deleteTarget.name}`}
          affectedItem={deleteTarget.name}
          consequence="Deleting this brand removes the canonical brand link from all mapped products."
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
