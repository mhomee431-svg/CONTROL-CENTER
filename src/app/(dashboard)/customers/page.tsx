'use client';

import React, { useState } from 'react';
import { useRouter } from 'next/navigation';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, Button, MenuItem, Select, FormControl, InputLabel } from '@mui/material';
import { UserX, CheckCircle, Eye } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AdminUserItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';

export default function CustomersPage() {
  const router = useRouter();
  const queryClient = useQueryClient();

  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('');

  // Confirmation modal state
  const [actionTarget, setActionTarget] = useState<{ id: number; name: string; action: 'SUSPEND' | 'ACTIVATE' | 'BAN' } | null>(null);

  // TanStack Query for Customers
  const { data, isLoading, refetch } = useQuery<{ items: AdminUserItem[]; total: number }>({
    queryKey: ['admin', 'customers', { page: paginationModel.page, pageSize: paginationModel.pageSize, search, status: statusFilter }],
    queryFn: () =>
      apiClient<{ items: AdminUserItem[]; total: number }>(API_ENDPOINTS.CUSTOMERS.LIST, {
        params: {
          role: 'customer',
          status: statusFilter || undefined,
          search: search || undefined,
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
  });

  // Status Change Mutation
  const statusMutation = useMutation({
    mutationFn: ({ userId, action, reason }: { userId: number; action: string; reason: string }) =>
      apiClient(API_ENDPOINTS.CUSTOMERS.STATUS(userId), {
        method: 'POST',
        params: { action, reason },
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin', 'customers'] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'dashboard', 'metrics'] });
    },
  });

  const handleConfirmAction = async (reason: string) => {
    if (!actionTarget) return;
    await statusMutation.mutateAsync({
      userId: actionTarget.id,
      action: actionTarget.action,
      reason,
    });
  };

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    {
      field: 'name',
      headerName: 'Customer Name',
      flex: 1.2,
      minWidth: 160,
      renderCell: (params) => (
        <Typography variant="body2" sx={{ fontWeight: 600 }}>
          {params.value || 'Anonymous Customer'}
        </Typography>
      ),
    },
    { field: 'phone', headerName: 'Phone Number', flex: 1, minWidth: 140 },
    {
      field: 'status',
      headerName: 'Status',
      width: 130,
      renderCell: (params) => <StatusBadge status={params.value as string} />,
    },
    {
      field: 'created_at',
      headerName: 'Registered At',
      flex: 1,
      minWidth: 160,
      valueFormatter: (value) => (value ? new Date(value as string).toLocaleDateString() : 'N/A'),
    },
    {
      field: 'actions',
      headerName: 'Actions',
      width: 220,
      sortable: false,
      renderCell: (params) => {
        const item = params.row as AdminUserItem;
        const isSuspended = item.status === 'SUSPENDED';

        return (
          <Box sx={{ display: 'flex', gap: 1 }}>
            <Button
              size="small"
              variant="text"
              startIcon={<Eye size={14} />}
              onClick={() => router.push(`/customers/${item.id}`)}
            >
              View
            </Button>
            <PermissionGuard capability={CAPABILITIES.CUSTOMERS_SUSPEND}>
              {isSuspended ? (
                <Button
                  size="small"
                  color="success"
                  variant="outlined"
                  startIcon={<CheckCircle size={14} />}
                  onClick={() => setActionTarget({ id: item.id, name: item.name || `User #${item.id}`, action: 'ACTIVATE' })}
                >
                  Reactivate
                </Button>
              ) : (
                <Button
                  size="small"
                  color="error"
                  variant="outlined"
                  startIcon={<UserX size={14} />}
                  onClick={() => setActionTarget({ id: item.id, name: item.name || `User #${item.id}`, action: 'SUSPEND' })}
                >
                  Suspend
                </Button>
              )}
            </PermissionGuard>
          </Box>
        );
      },
    },
  ];

  return (
    <Box>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Customer Management
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Monitor customer accounts, review registration activity, and govern account standing.
        </Typography>
      </Box>

      {/* Filter Bar */}
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
            <MenuItem value="SUSPENDED">Suspended</MenuItem>
            <MenuItem value="INACTIVE">Inactive</MenuItem>
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
        searchPlaceholder="Search by name or phone..."
        searchValue={search}
        onSearchChange={setSearch}
        onRefresh={() => refetch()}
      />

      {/* Confirmation Modal */}
      {actionTarget && (
        <ConfirmationDialog
          open={Boolean(actionTarget)}
          title={`${actionTarget.action === 'ACTIVATE' ? 'Reactivate' : 'Suspend'} Customer Account`}
          affectedItem={actionTarget.name}
          consequence={
            actionTarget.action === 'SUSPEND'
              ? 'Suspended customers cannot log in, search for nearby inventory, or interact with businesses.'
              : 'The customer will immediately regain access to platform discovery services.'
          }
          isDangerous={actionTarget.action === 'SUSPEND'}
          requireReason
          isLoading={statusMutation.isPending}
          onConfirm={handleConfirmAction}
          onClose={() => setActionTarget(null)}
        />
      )}
    </Box>
  );
}
