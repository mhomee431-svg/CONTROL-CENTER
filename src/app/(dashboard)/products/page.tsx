'use client';

import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel, GridRowSelectionModel } from '@mui/x-data-grid';
import { Box, Typography, Button, MenuItem, Select, FormControl, InputLabel } from '@mui/material';
import { Package, Check, Archive, XCircle } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { ProductItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';

export default function ProductsPage() {
  const queryClient = useQueryClient();

  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [rowSelectionModel, setRowSelectionModel] = useState<GridRowSelectionModel>([]);

  // Bulk action modal state
  const [bulkAction, setBulkAction] = useState<'APPROVE' | 'REJECT' | 'ARCHIVE' | null>(null);

  const { data, isLoading, refetch } = useQuery<{ items: ProductItem[]; total: number }>({
    queryKey: ['admin', 'products', { page: paginationModel.page, pageSize: paginationModel.pageSize, search, status: statusFilter }],
    queryFn: () =>
      apiClient<{ items: ProductItem[]; total: number }>(API_ENDPOINTS.PRODUCTS.LIST, {
        params: {
          status: statusFilter || undefined,
          search: search || undefined,
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
  });

  const bulkMutation = useMutation({
    mutationFn: ({ action, product_ids, reason }: { action: string; product_ids: number[]; reason: string }) =>
      apiClient(API_ENDPOINTS.PRODUCTS.BULK, {
        method: 'POST',
        body: JSON.stringify({ action, product_ids, reason }),
      }),
    onSuccess: () => {
      setRowSelectionModel([]);
      queryClient.invalidateQueries({ queryKey: ['admin', 'products'] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'dashboard', 'metrics'] });
    },
  });

  const handleConfirmBulk = async (reason: string) => {
    if (!bulkAction || rowSelectionModel.length === 0) return;
    await bulkMutation.mutateAsync({
      action: bulkAction,
      product_ids: rowSelectionModel.map((id) => Number(id)),
      reason,
    });
  };

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    {
      field: 'name',
      headerName: 'Master Product Name',
      flex: 1.5,
      minWidth: 200,
      renderCell: (params) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <Package size={16} color="#10B981" />
          <Typography variant="body2" sx={{ fontWeight: 600 }}>
            {params.value as string}
          </Typography>
        </Box>
      ),
    },
    {
      field: 'brand_name',
      headerName: 'Brand',
      flex: 1,
      minWidth: 120,
      valueGetter: (_, row) => row.brand_name || 'Generic / Unbranded',
    },
    {
      field: 'category_name',
      headerName: 'Category',
      flex: 1,
      minWidth: 140,
      valueGetter: (_, row) => row.category_name || 'Unassigned',
    },
    { field: 'barcode', headerName: 'Barcode / EAN', flex: 1, minWidth: 140 },
    {
      field: 'status',
      headerName: 'Status',
      width: 130,
      renderCell: (params) => <StatusBadge status={params.value as string} />,
    },
    {
      field: 'shop_count',
      headerName: 'Stocked In',
      width: 100,
      align: 'right',
      headerAlign: 'right',
      valueFormatter: (value) => (value ? `${value} shops` : '0 shops'),
    },
  ];

  return (
    <Box>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Master Product Catalog
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Platform-wide canonical catalog. Products, brand linkages, barcodes, and bulk moderation.
        </Typography>
      </Box>

      {/* Filters */}
      <Box sx={{ mb: 2, display: 'flex', gap: 2 }}>
        <FormControl size="small" sx={{ minWidth: 160 }}>
          <InputLabel>Status</InputLabel>
          <Select
            value={statusFilter}
            label="Status"
            onChange={(e) => setStatusFilter(e.target.value)}
          >
            <MenuItem value="">All Statuses</MenuItem>
            <MenuItem value="ACTIVE">Active</MenuItem>
            <MenuItem value="PENDING">Pending</MenuItem>
            <MenuItem value="ARCHIVED">Archived</MenuItem>
          </Select>
        </FormControl>
      </Box>

      <AdminDataGrid
        rows={(data?.items || []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        searchPlaceholder="Search product by name, brand, or barcode..."
        searchValue={search}
        onSearchChange={setSearch}
        onRefresh={() => refetch()}
        checkboxSelection
        rowSelectionModel={rowSelectionModel}
        onRowSelectionModelChange={setRowSelectionModel}
        bulkActions={
          rowSelectionModel.length > 0 ? (
            <Box sx={{ display: 'flex', gap: 1 }}>
              <Button
                size="small"
                variant="contained"
                color="success"
                startIcon={<Check size={14} />}
                onClick={() => setBulkAction('APPROVE')}
              >
                Approve ({rowSelectionModel.length})
              </Button>
              <Button
                size="small"
                variant="outlined"
                color="error"
                startIcon={<XCircle size={14} />}
                onClick={() => setBulkAction('REJECT')}
              >
                Reject ({rowSelectionModel.length})
              </Button>
              <Button
                size="small"
                variant="outlined"
                color="inherit"
                startIcon={<Archive size={14} />}
                onClick={() => setBulkAction('ARCHIVE')}
              >
                Archive
              </Button>
            </Box>
          ) : undefined
        }
      />

      {bulkAction && (
        <ConfirmationDialog
          open={Boolean(bulkAction)}
          title={`Bulk ${bulkAction} Products`}
          affectedItem={`${rowSelectionModel.length} selected products`}
          consequence={
            bulkAction === 'ARCHIVE'
              ? 'Archived products will no longer be discoverable by customers or linkable by shopkeepers.'
              : `Selected products will be moved to ${bulkAction} status across the entire master database.`
          }
          isDangerous={bulkAction === 'ARCHIVE' || bulkAction === 'REJECT'}
          requireReason
          isLoading={bulkMutation.isPending}
          onConfirm={handleConfirmBulk}
          onClose={() => setBulkAction(null)}
        />
      )}
    </Box>
  );
}
