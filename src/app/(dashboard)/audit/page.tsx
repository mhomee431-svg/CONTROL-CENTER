'use client';

import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, MenuItem, Select, FormControl, InputLabel } from '@mui/material';
import { FileText, Shield } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AuditLogItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';

export default function AuditLogsPage() {
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [entityFilter, setEntityFilter] = useState('');

  const { data, isLoading, isError, refetch } = useQuery<{ items: AuditLogItem[]; total: number }>({
    queryKey: ['admin', 'audit-logs', { page: paginationModel.page, pageSize: paginationModel.pageSize, entityFilter }],
    queryFn: () =>
      apiClient<{ items: AuditLogItem[]; total: number }>(API_ENDPOINTS.AUDIT.LOGS, {
        params: {
          entity_type: entityFilter || undefined,
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
  });

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    {
      field: 'action',
      headerName: 'Operation / Action',
      flex: 1.2,
      minWidth: 160,
      renderCell: (params) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <Shield size={16} color="#0F52BA" />
          <Typography variant="body2" sx={{ fontWeight: 600 }}>
            {params.value as string}
          </Typography>
        </Box>
      ),
    },
    { field: 'entity_type', headerName: 'Target Entity', width: 140 },
    { field: 'entity_id', headerName: 'Entity ID', width: 100 },
    {
      field: 'admin_user',
      headerName: 'Operator / Admin',
      flex: 1,
      minWidth: 140,
      valueGetter: (_, row) => row.admin_user || `User #${row.user_id || 'System'}`,
    },
    { field: 'ip_address', headerName: 'Client IP', width: 140 },
    {
      field: 'created_at',
      headerName: 'Timestamp',
      flex: 1.2,
      minWidth: 180,
      valueFormatter: (value) => (value ? new Date(value as string).toLocaleString() : 'N/A'),
    },
  ];

  return (
    <Box>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Platform Audit Logs
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Section 73 & 172: Immutable administrative record. Every sensitive status change, approval, and config edit is tracked.
        </Typography>
      </Box>

      <Box sx={{ mb: 2, display: 'flex', gap: 2 }}>
        <FormControl size="small" sx={{ minWidth: 160 }}>
          <InputLabel>Entity Type</InputLabel>
          <Select
            value={entityFilter}
            label="Entity Type"
            onChange={(e) => setEntityFilter(e.target.value)}
          >
            <MenuItem value="">All Entities</MenuItem>
            <MenuItem value="SHOP">Shop</MenuItem>
            <MenuItem value="USER">User / Customer</MenuItem>
            <MenuItem value="PRODUCT">Product</MenuItem>
            <MenuItem value="CATEGORY">Category</MenuItem>
            <MenuItem value="SETTING">System Setting</MenuItem>
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
        onRefresh={() => refetch()}
        error={isError}
      />
    </Box>
  );
}
