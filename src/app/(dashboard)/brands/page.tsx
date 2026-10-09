'use client';

import { useCallback, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, Button } from '@mui/material';
import { Plus, Tag } from 'lucide-react';
import { BrandDialog } from './BrandDialog';
import { BrandStatusSwitch } from './BrandStatusSwitch';
import { BrandItemRowActions } from './BrandItemRowActions';
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
  const [openEdit, setOpenEdit] = useState(false);
  const [openDuplicate, setOpenDuplicate] = useState(false);
  const [editBrand, setEditBrand] = useState<BrandItem | null>(null);
  const [duplicateSource, setDuplicateSource] = useState<BrandItem | null>(null);
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
      queryClient.invalidateQueries({ queryKey: ['admin', 'brands'] });
      refetch();
    },
  });

  const editMutation = useMutation({
    mutationFn: (brand: BrandItem) =>
      apiClient(API_ENDPOINTS.BRANDS.UPDATE(brand.id), {
        method: 'PATCH',
        body: JSON.stringify({
          name: brand.name,
          slug: brand.slug,
          description: brand.description || undefined,
          is_active: brand.is_active,
        }),
      }),
    onSuccess: () => {
      setOpenEdit(false);
      setEditBrand(null);
      queryClient.invalidateQueries({ queryKey: ['admin', 'brands'] });
      refetch();
    },
  });

  const duplicateMutation = useMutation({
    mutationFn: (source: BrandItem) =>
      apiClient(API_ENDPOINTS.BRANDS.CREATE, {
        method: 'POST',
        body: JSON.stringify({
          name: `${source.name} (Copy)`,
          slug: source.slug,
          description: `Copy of ${source.name}`,
          is_active: true,
        }),
      }),
    onSuccess: () => {
      setOpenDuplicate(false);
      setDuplicateSource(null);
      queryClient.invalidateQueries({ queryKey: ['admin', 'brands'] });
      refetch();
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
      refetch();
    },
  });

  // Status toggle: flips is_active on the backend (never deletes).
  const statusMutation = useMutation({
    mutationFn: (brand: BrandItem) =>
      apiClient(API_ENDPOINTS.BRANDS.UPDATE(brand.id), {
        method: 'PATCH',
        body: JSON.stringify({ is_active: !brand.is_active }),
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin', 'brands'] });
      refetch();
    },
  });

  const handleEdit = useCallback((brand: BrandItem) => {
    setEditBrand(brand);
    setOpenEdit(true);
  }, []);

  const handleDuplicate = useCallback((brand: BrandItem) => {
    setDuplicateSource(brand);
    setOpenDuplicate(true);
  }, []);

  const handleDelete = useCallback((brand: BrandItem) => {
    // Open the confirmation dialog — the actual delete runs from its confirm
    // handler (reason required), so a stray click can never destroy a brand.
    setDeleteTarget(brand);
  }, []);

  const handleStatusToggle = useCallback(
    (brand: BrandItem) => {
      statusMutation.mutate(brand);
    },
    [statusMutation],
  );

  const handleEditSaved = useCallback(() => {
    editMutation.mutate(editBrand!);
  }, [editBrand, editMutation]);

  const handleDuplicateSaved = useCallback(() => {
    duplicateMutation.mutate(duplicateSource!);
  }, [duplicateSource, duplicateMutation]);

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
          <BrandItemRowActions
            row={item}
            excluded={false}
            onEdit={handleEdit}
            onDuplicate={handleDuplicate}
            onStatusToggle={handleStatusToggle}
            onDelete={handleDelete}
          />
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
      <BrandDialog
        open={openCreate}
        mode="create"
        onClose={() => setOpenCreate(false)}
        onSaved={() => setOpenCreate(false)}
      />

      {/* Edit Dialog */}
      <BrandDialog
        open={openEdit}
        mode="edit"
        brand={editBrand}
        onClose={() => setOpenEdit(false)}
        onSaved={() => setOpenEdit(false)}
      />

      {/* Duplicate Dialog */}
      <BrandDialog
        open={openDuplicate}
        mode="duplicate"
        sourceBrand={duplicateSource}
        onClose={() => setOpenDuplicate(false)}
        onSaved={() => setOpenDuplicate(false)}
      />

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
