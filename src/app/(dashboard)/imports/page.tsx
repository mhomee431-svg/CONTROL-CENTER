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

interface ImportJob {
  id: number;
  source?: string;
  status?: string;
  rows_total?: number;
  rows_processed?: number;
  created_at?: string;
}

export default function ImportsPage() {
  const router = useRouter();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [search, setSearch] = useState('');

  const { data, isLoading, isError, refetch } = useQuery<{ items: ImportJob[]; total: number }>({
    queryKey: ['admin', 'imports', { page: paginationModel.page, pageSize: paginationModel.pageSize, search }],
    queryFn: () =>
      // Dedicated import-job endpoint. This previously called
      // /admin/reports and rendered report rows as import jobs, which produced
      // an entirely empty grid: the two payloads share no fields.
      apiClient<{ items: ImportJob[]; total: number }>(API_ENDPOINTS.INGESTION.IMPORTS, {
        params: {
          search: search || undefined,
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
    retry: false,
  });

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'Job ID', width: 90 },
    { field: 'source', headerName: 'Source', flex: 1.5, minWidth: 160 },
    {
      field: 'status',
      headerName: 'Status',
      width: 130,
      renderCell: (params) => <StatusBadge status={(params.value as string) || 'UNKNOWN'} />,
    },
    { field: 'rows_total', headerName: 'Total Rows', width: 130, align: 'right', headerAlign: 'right' },
    { field: 'rows_processed', headerName: 'Processed', width: 130, align: 'right', headerAlign: 'right' },
    {
      field: 'created_at',
      headerName: 'Started',
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
          { label: 'Imports' },
        ]}
      />
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Data Ingestion & Import Jobs
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Monitor bulk catalog, inventory, and merchant data ingestion pipelines.
        </Typography>
      </Box>

      {isError && (
        <Alert severity="error" sx={{ mb: 2 }}>
          Import job telemetry is unavailable. The backend has not published the import-job
          endpoint, so no rows are shown rather than substituting unrelated data.
        </Alert>
      )}

      <AdminDataGrid
        rows={(data?.items || []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        searchPlaceholder="Search import jobs..."
        searchValue={search}
        onSearchChange={setSearch}
        onRefresh={() => refetch()}
        onRowClick={(params) => router.push(ROUTES.IMPORT_DETAIL(params.row.id as number))}
      />
    </Box>
  );
}
