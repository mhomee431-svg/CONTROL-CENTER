'use client';

import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, Button } from '@mui/material';
import { DollarSign, PauseCircle, PlayCircle } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { OfferItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';

export default function OffersPage() {
  const queryClient = useQueryClient();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [actionTarget, setActionTarget] = useState<{ id: number; title: string; nextStatus: 'ACTIVE' | 'PAUSED' } | null>(null);

  const { data, isLoading, isError, refetch } = useQuery<{ items: OfferItem[]; total: number }>({
    queryKey: ['admin', 'offers', { page: paginationModel.page, pageSize: paginationModel.pageSize }],
    queryFn: () =>
      apiClient<{ items: OfferItem[]; total: number }>(API_ENDPOINTS.OFFERS.LIST, {
        params: {
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, new_status }: { id: number; new_status: string }) =>
      apiClient(API_ENDPOINTS.OFFERS.UPDATE_STATUS(id), {
        method: 'POST',
        body: JSON.stringify({ new_status }),
      }),
    onSuccess: () => {
      setActionTarget(null);
      queryClient.invalidateQueries({ queryKey: ['admin', 'offers'] });
    },
  });

  const handleConfirm = async () => {
    if (!actionTarget) return;
    await updateMutation.mutateAsync({
      id: actionTarget.id,
      new_status: actionTarget.nextStatus,
    });
  };

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 70 },
    {
      field: 'title',
      headerName: 'Offer Campaign',
      flex: 1.5,
      minWidth: 180,
      renderCell: (params) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <DollarSign size={16} color="#10B981" />
          <Typography variant="body2" sx={{ fontWeight: 600 }}>
            {params.value as string}
          </Typography>
        </Box>
      ),
    },
    { field: 'shop_name', headerName: 'Retail Shop', flex: 1.2, minWidth: 150 },
    {
      field: 'discount_value',
      headerName: 'Discount',
      width: 120,
      valueGetter: (_, row) => `${row.discount_value}${row.discount_type === 'PERCENTAGE' ? '%' : ' OFF'}`,
    },
    {
      field: 'status',
      headerName: 'Status',
      width: 120,
      renderCell: (params) => <StatusBadge status={params.value as string} />,
    },
    {
      field: 'valid_until',
      headerName: 'Valid Until',
      flex: 1,
      minWidth: 140,
      valueFormatter: (value) => (value ? new Date(value as string).toLocaleDateString() : 'N/A'),
    },
    {
      field: 'actions',
      headerName: 'Actions',
      width: 140,
      sortable: false,
      renderCell: (params) => {
        const item = params.row as OfferItem;
        const isActive = item.status === 'ACTIVE';
        return (
          <PermissionGuard capability={CAPABILITIES.OFFERS_UPDATE}>
            <Button
              size="small"
              color={isActive ? 'warning' : 'success'}
              startIcon={isActive ? <PauseCircle size={14} /> : <PlayCircle size={14} />}
              onClick={() => setActionTarget({ id: item.id, title: item.title, nextStatus: isActive ? 'PAUSED' : 'ACTIVE' })}
            >
              {isActive ? 'Pause' : 'Activate'}
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
          Offers & Promotional Campaigns
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Section 40: Review active discounts and govern promotional integrity.
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
        error={isError}
      />

      {actionTarget && (
        <ConfirmationDialog
          open={Boolean(actionTarget)}
          title={`${actionTarget.nextStatus === 'PAUSED' ? 'Pause' : 'Activate'} Offer`}
          affectedItem={actionTarget.title}
          consequence="Altering the status of this offer changes the pricing badge displayed to nearby shoppers."
          isDangerous={actionTarget.nextStatus === 'PAUSED'}
          requireReason
          isLoading={updateMutation.isPending}
          onConfirm={handleConfirm}
          onClose={() => setActionTarget(null)}
        />
      )}
    </Box>
  );
}
