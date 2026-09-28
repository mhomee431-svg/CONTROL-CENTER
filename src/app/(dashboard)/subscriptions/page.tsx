'use client';

import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography } from '@mui/material';
import { DollarSign } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';

interface SubscriptionItem {
  id: number;
  shop_name: string;
  plan_name: string;
  amount: number;
  status: string;
  renews_at?: string;
}

export default function SubscriptionsPage() {
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });

  const { data, isLoading, refetch } = useQuery<{ items: SubscriptionItem[]; total: number }>({
    queryKey: ['admin', 'subscriptions', { page: paginationModel.page, pageSize: paginationModel.pageSize }],
    queryFn: () =>
      apiClient<{ items: SubscriptionItem[]; total: number }>(API_ENDPOINTS.SUBSCRIPTIONS.LIST, {
        params: {
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
  });

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
