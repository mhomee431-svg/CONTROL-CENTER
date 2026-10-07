'use client';

import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, Alert } from '@mui/material';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';

interface PaymentItem {
  id: number;
  shop_name?: string | null;
  amount: number;
  status: string;
  method?: string | null;
  invoice_id?: string | null;
  paid_at?: string | null;
  created_at?: string;
}

export default function PaymentsPage() {
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });

  const { data, isLoading, isError, refetch } = useQuery<{ items: PaymentItem[]; total: number }>({
    queryKey: ['admin', 'payments', { page: paginationModel.page, pageSize: paginationModel.pageSize }],
    queryFn: () =>
      apiClient<{ items: PaymentItem[]; total: number }>(API_ENDPOINTS.SUBSCRIPTIONS.PAYMENTS, {
        params: {
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
  });

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    {
      field: 'shop_name',
      headerName: 'Merchant',
      flex: 1.3,
      minWidth: 180,
      valueGetter: (_, row) => row.shop_name || `Shop #${row.shop_id ?? '—'}`,
    },
    {
      field: 'amount',
      headerName: 'Amount',
      width: 130,
      align: 'right',
      headerAlign: 'right',
      valueFormatter: (value) => `₹${Number(value ?? 0).toFixed(2)}`,
    },
    {
      field: 'status',
      headerName: 'Status',
      width: 130,
      renderCell: (params) => <StatusBadge status={params.value as string} />,
    },
    { field: 'method', headerName: 'Method', width: 130 },
    { field: 'invoice_id', headerName: 'Invoice', width: 150 },
    {
      field: 'paid_at',
      headerName: 'Paid At',
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
          { label: 'Subscriptions', href: ROUTES.SUBSCRIPTIONS },
          { label: 'Payments' },
        ]}
      />
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Merchant Payments
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Transaction ledger backing the merchant subscription programme.
        </Typography>
      </Box>

      {isError && (
        <Alert severity="error" sx={{ mb: 2 }}>
          Could not load the payments ledger.
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