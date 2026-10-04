'use client';

import React, { useState, useEffect } from 'react';
import { useSearchParams } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography } from '@mui/material';
import { Store } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AdminUserItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';

function ShopkeepersContent() {
  const searchParams = useSearchParams();
  const highlightId = searchParams.get('highlight');
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [search, setSearch] = useState('');

  // Highlight a specific shopkeeper when drilling down from a shop or inventory record
  useEffect(() => {
    if (highlightId) setSearch('');
  }, [highlightId]);

  const { data, isLoading, refetch } = useQuery<{ items: AdminUserItem[]; total: number }>({
    queryKey: ['admin', 'shopkeepers', { page: paginationModel.page, pageSize: paginationModel.pageSize, search }],
    queryFn: () =>
      apiClient<{ items: AdminUserItem[]; total: number }>(API_ENDPOINTS.CUSTOMERS.LIST, {
        params: {
          role: 'shopkeeper',
          search: search || undefined,
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
  });

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80, cellClassName: (params) => (String(params.value) === highlightId ? 'highlighted-row' : '') },
    {
      field: 'name',
      headerName: 'Shopkeeper Name',
      flex: 1.5,
      minWidth: 180,
      renderCell: (params) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <Store size={16} color="#0F52BA" />
          <Typography variant="body2" sx={{ fontWeight: 600 }}>
            {params.value || 'Registered Shopkeeper'}
          </Typography>
        </Box>
      ),
    },
    { field: 'phone', headerName: 'Contact Phone', flex: 1, minWidth: 140 },
    {
      field: 'status',
      headerName: 'Account Status',
      width: 140,
      renderCell: (params) => <StatusBadge status={params.value as string} />,
    },
    {
      field: 'created_at',
      headerName: 'Registered Date',
      flex: 1,
      minWidth: 160,
      valueFormatter: (value) => (value ? new Date(value as string).toLocaleDateString() : 'N/A'),
    },
  ];

  return (
    <Box>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Shopkeeper Account Registry
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Section 23 & 24: Merchant owners and retail store operators.
        </Typography>
      </Box>

      <AdminDataGrid
        rows={(data?.items || []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        searchPlaceholder="Search shopkeeper by name or phone..."
        searchValue={search}
        onSearchChange={setSearch}
        onRefresh={() => refetch()}
      />
    </Box>
  );
}

export default function ShopkeepersPage() {
  return (
    <React.Suspense fallback={null}>
      <ShopkeepersContent />
    </React.Suspense>
  );
}
