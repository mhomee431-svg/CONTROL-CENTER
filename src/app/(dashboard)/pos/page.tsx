'use client';

import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, Alert } from '@mui/material';
import { useRouter } from 'next/navigation';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
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
  const [search, setSearch] = useState('');

  const { data, isLoading, isError, refetch } = useQuery<{ items: PosIntegration[]; total: number }>({
    queryKey: ['admin', 'pos', { page: paginationModel.page, pageSize: paginationModel.pageSize, search }],
    queryFn: () =>
      // Dedicated POS integration endpoint. This previously called
      // /admin/shops, whose payload has no provider/status/last_sync fields,
      // so every column rendered blank for every row.
      apiClient<{ items: PosIntegration[]; total: number }>(API_ENDPOINTS.INGESTION.POS_INTEGRATIONS, {
        params: {
          search: search || undefined,
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
      valueGetter: (_, row) => (row as PosIntegration).shop_name || 'Merchant',
    },
    { field: 'provider', headerName: 'POS Provider', flex: 1, minWidth: 150 },
    {
      field: 'status',
      headerName: 'Sync Status',
      width: 140,
      renderCell: (params) => <StatusBadge status={(params.value as string) || 'UNKNOWN'} />,
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

      {isError && (
        <Alert severity="error" sx={{ mb: 2 }}>
          POS integration telemetry is unavailable. The backend has not published the POS endpoint, so
          no rows are shown rather than substituting unrelated shop data.
        </Alert>
      )}

      <AdminDataGrid
        rows={(data?.items || []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        searchPlaceholder="Search POS integrations..."
        searchValue={search}
        onSearchChange={setSearch}
        onRefresh={() => refetch()}
        onRowClick={(params) => router.push(ROUTES.POS_DETAIL(params.row.id as number))}
      />
    </Box>
  );
}
