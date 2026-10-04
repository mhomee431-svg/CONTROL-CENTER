'use client';

import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, Alert } from '@mui/material';
import { useRouter } from 'next/navigation';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { ShopItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';

interface PosIntegration {
  id: number;
  shop_name?: string;
  provider?: string;
  status?: string;
  last_sync?: string;
}

export default function PosPage() {
  const router = useRouter();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });

  const { data, isLoading, refetch } = useQuery<{ items: PosIntegration[]; total: number }>({
    queryKey: ['admin', 'pos', paginationModel],
    queryFn: () =>
      apiClient<{ items: PosIntegration[]; total: number }>(API_ENDPOINTS.SHOPS.LIST, {
        params: {
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
    retry: false,
  });

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 90 },
    {
      field: 'shop_name',
      headerName: 'Shop',
      flex: 1.5,
      minWidth: 180,
      valueGetter: (_, row) => (row as ShopItem).name || (row as PosIntegration).shop_name || 'Merchant',
    },
    { field: 'provider', headerName: 'POS Provider', flex: 1, minWidth: 150 },
    {
      field: 'status',
      headerName: 'Sync Status',
      width: 140,
      renderCell: (params) => <StatusBadge status={(params.value as string) || 'QUEUED'} />,
    },
    {
      field: 'last_sync',
      headerName: 'Last Sync',
      flex: 1.2,
      minWidth: 170,
      valueFormatter: (value) => (value ? new Date(value as string).toLocaleString() : 'N/A'),
    },
  ];

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'POS Integrations' },
        ]}
      />
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          POS Integration Monitor
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Track merchant point-of-sale sync connections and inventory ingestion health.
        </Typography>
      </Box>

      <Alert severity="info" sx={{ mb: 2 }}>
        POS provider mappings are returned by the backend integration endpoint; the registry lists connected shops.
      </Alert>

      <AdminDataGrid
        rows={(data?.items || []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        searchPlaceholder="Search POS integrations..."
        onRefresh={() => refetch()}
        onRowClick={(params) => router.push(ROUTES.POS_DETAIL(params.row.id as number))}
      />
    </Box>
  );
}
