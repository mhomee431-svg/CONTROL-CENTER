'use client';

import React, { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, Button, Alert } from '@mui/material';
import { DollarSign } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';

interface SubscriptionItem {
  id: number;
  shop_name: string;
  plan_name: string;
  amount: number;
  status: string;
  renews_at?: string;
}

/** Status transitions the backend accepts on a subscription. */
const SUBSCRIPTION_STATUSES = ['ACTIVE', 'PAUSED', 'CANCELLED', 'EXPIRED'] as const;

export default function SubscriptionsPage() {
  const queryClient = useQueryClient();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });

  const { data, isLoading, isError, refetch } = useQuery<{ items: SubscriptionItem[]; total: number }>({
    queryKey: ['admin', 'subscriptions', { page: paginationModel.page, pageSize: paginationModel.pageSize }],
    queryFn: () =>
      apiClient<{ items: SubscriptionItem[]; total: number }>(API_ENDPOINTS.SUBSCRIPTIONS.LIST, {
        params: {
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
  });

  // Subscription status changes are audited by the backend, so every mutation
  // sends an explicit action and invalidates the list.
  const statusMutation = useMutation({
    mutationFn: ({ id, status }: { id: number; status: string }) =>
      apiClient(API_ENDPOINTS.SUBSCRIPTIONS.UPDATE(id), {
        method: 'PUT',
        body: JSON.stringify({ status }),
      }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['admin', 'subscriptions'] }),
  });

  const cycleStatus = (row: SubscriptionItem) => {
    const idx = SUBSCRIPTION_STATUSES.indexOf(row.status as (typeof SUBSCRIPTION_STATUSES)[number]);
    const next = SUBSCRIPTION_STATUSES[(idx + 1) % SUBSCRIPTION_STATUSES.length];
    statusMutation.mutate({ id: row.id, status: next });
  };

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 70 },
    {
      field: 'shop_name',
      headerName: 'Subscribing Business',
      flex: 1.5,
      minWidth: 180,
      renderCell: (params) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <DollarSign size={16} color="#0F52BA" />
          <Typography variant="body2" sx={{ fontWeight: 600 }}>
            {params.value || 'Retail Merchant'}
          </Typography>
        </Box>
      ),
    },
    { field: 'plan_name', headerName: 'Tier / Plan', flex: 1, minWidth: 140 },
    {
      field: 'amount',
      headerName: 'Fee',
      width: 120,
      valueFormatter: (value) => (value ? `₹${Number(value).toFixed(2)}` : 'N/A'),
    },
    {
      field: 'status',
      headerName: 'Status',
      width: 130,
      renderCell: (params) => <StatusBadge status={params.value as string} />,
    },
    {
      field: 'renews_at',
      headerName: 'Renewal Date',
      flex: 1,
      minWidth: 160,
      valueFormatter: (value) => (value ? new Date(value as string).toLocaleDateString() : 'N/A'),
    },
    {
      field: 'actions',
      headerName: 'Actions',
      width: 170,
      sortable: false,
      renderCell: (params) => {
        const row = params.row as unknown as SubscriptionItem;
        return (
          <PermissionGuard capability={CAPABILITIES.SUBSCRIPTIONS_UPDATE}>
            <Button
              size="small"
              variant="outlined"
              disabled={statusMutation.isPending}
              onClick={(e) => {
                e.stopPropagation();
                cycleStatus(row);
              }}
            >
              Change Status
            </Button>
          </PermissionGuard>
        );
      },
    },
  ];

  return (
    <Box>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Shopkeeper Subscriptions & Monetization
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Section 220: Platform merchant subscription plans, renewals, and monetization tracking.
        </Typography>
      </Box>

      {isError && (
        <Alert severity="error" sx={{ mb: 2 }}>
          Could not load subscriptions.
        </Alert>
      )}

      <AdminDataGrid
        rows={(data?.items || []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        onRefresh={() => refetch()}
      />
    </Box>
  );
}
