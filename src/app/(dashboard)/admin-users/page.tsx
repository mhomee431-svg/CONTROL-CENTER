'use client';

import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography } from '@mui/material';
import { useRouter } from 'next/navigation';
import { ShieldCheck } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AdminUserItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { getRoleLabel } from '@/core/permissions/permissions';
import { ROUTES } from '@/core/routes/routes';

/**
 * Admin Users registry — the RBAC management surface. Only roles carrying
 * `admins.read` see it (enforced by the sidebar capability filter and the
 * backend endpoint).
 */
export default function AdminUsersPage() {
  const router = useRouter();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });

  const { data, isLoading, refetch } = useQuery<{ items: AdminUserItem[]; total: number }>({
    queryKey: ['admin', 'admin-users', paginationModel],
    queryFn: () =>
      apiClient<{ items: AdminUserItem[]; total: number }>(API_ENDPOINTS.CUSTOMERS.LIST, {
        params: {
          role: 'admin',
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
  });

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    {
      field: 'name',
      headerName: 'Administrator',
      flex: 1.5,
      minWidth: 180,
      renderCell: (params) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <ShieldCheck size={16} color="#0F52BA" />
          <Typography variant="body2" sx={{ fontWeight: 600 }}>
            {(params.value as string) || 'Administrator'}
          </Typography>
        </Box>
      ),
    },
    { field: 'phone', headerName: 'Contact Phone', flex: 1, minWidth: 140 },
    {
      field: 'role',
      headerName: 'Role',
      flex: 1,
      minWidth: 160,
      valueGetter: (_, row) =>
        getRoleLabel({
          user_id: (row as AdminUserItem).id,
          name: (row as AdminUserItem).name,
          role_name: (row as AdminUserItem).role,
          level: 'SUB',
          permissions: [],
        }),
    },
    {
      field: 'status',
      headerName: 'Status',
      width: 130,
      renderCell: (params) => <StatusBadge status={params.value as string} />,
    },
    {
      field: 'created_at',
      headerName: 'Registered',
      flex: 1,
      minWidth: 160,
      valueFormatter: (value) => (value ? new Date(value as string).toLocaleDateString() : 'N/A'),
    },
  ];

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Admin Users' },
        ]}
      />
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Administrator Registry (RBAC)
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Centralized management of platform administrators, roles, and permissions.
        </Typography>
      </Box>

      <AdminDataGrid
        rows={(data?.items || []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        searchPlaceholder="Search administrators..."
        onRefresh={() => refetch()}
        onRowClick={(params) => router.push(ROUTES.ADMIN_USER_DETAIL(params.row.id as number))}
      />
    </Box>
  );
}
