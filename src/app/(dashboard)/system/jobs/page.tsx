'use client';

import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, Alert } from '@mui/material';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AuditLogItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';

interface JobRow {
  id: number;
  action: string;
  entity_type: string;
  status?: string;
  created_at: string;
}

export default function SystemJobsPage() {
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });

  const { data, isLoading, refetch } = useQuery<{ items: AuditLogItem[]; total: number }>({
    queryKey: ['admin', 'system-jobs', paginationModel],
    queryFn: () =>
      apiClient<{ items: AuditLogItem[]; total: number }>(API_ENDPOINTS.AUDIT.ACTIONS, {
        params: {
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
    retry: false,
  });

  const rows: JobRow[] = (data?.items || []).map((item) => ({
    id: item.id,
    action: item.action,
    entity_type: item.entity_type,
    status: 'COMPLETED',
    created_at: item.created_at,
  }));

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'Job ID', width: 90 },
    { field: 'action', headerName: 'Job / Action', flex: 1.5, minWidth: 200 },
    { field: 'entity_type', headerName: 'Target Service', flex: 1, minWidth: 150 },
    {
      field: 'status',
      headerName: 'Status',
      width: 130,
      renderCell: (params) => <StatusBadge status={(params.value as string) || 'QUEUED'} />,
    },
    {
      field: 'created_at',
      headerName: 'Executed',
      flex: 1.2,
      minWidth: 180,
      valueFormatter: (value) => (value ? new Date(value as string).toLocaleString() : 'N/A'),
    },
  ];

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'System', href: ROUTES.SETTINGS },
          { label: 'Jobs' },
        ]}
      />
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Background Jobs Monitor
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Scheduled, asynchronous, and maintenance job execution across the platform.
        </Typography>
      </Box>

      <Alert severity="info" sx={{ mb: 2 }}>
        Job telemetry is sourced from the backend actions endpoint; scheduled queue state is backend-authoritative.
      </Alert>

      <AdminDataGrid
        rows={rows as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        searchPlaceholder="Search jobs..."
        onRefresh={() => refetch()}
      />
    </Box>
  );
}
