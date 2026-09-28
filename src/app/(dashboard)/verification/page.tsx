'use client';

import React, { useState } from 'react';
import { useRouter } from 'next/navigation';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, Button } from '@mui/material';
import { ShieldCheck, ShieldAlert, Eye, Store } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { ShopItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';

export default function VerificationPage() {
  const router = useRouter();
  const queryClient = useQueryClient();

  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [search, setSearch] = useState('');

  const [selectedCase, setSelectedCase] = useState<{ id: number; name: string; decision: 'VERIFY' | 'REJECT' } | null>(null);

  const { data, isLoading, refetch } = useQuery<{ items: ShopItem[]; total: number }>({
    queryKey: ['admin', 'verification-queue', { page: paginationModel.page, pageSize: paginationModel.pageSize, search }],
    queryFn: () =>
      apiClient<{ items: ShopItem[]; total: number }>(API_ENDPOINTS.SHOPS.LIST, {
        params: {
          verification_status: 'PENDING',
          search: search || undefined,
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
  });

  const verificationMutation = useMutation({
    mutationFn: ({ shopId, decision, reason }: { shopId: number; decision: string; reason: string }) =>
      apiClient(API_ENDPOINTS.SHOPS.VERIFICATION(shopId), {
        method: 'POST',
        body: JSON.stringify({ decision, reason }),
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin', 'verification-queue'] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'dashboard', 'metrics'] });
    },
  });

  const handleDecision = async (reason: string) => {
    if (!selectedCase) return;
    await verificationMutation.mutateAsync({
      shopId: selectedCase.id,
      decision: selectedCase.decision,
      reason,
    });
  };

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    {
      field: 'name',
      headerName: 'Shop Name',
      flex: 1.5,
      minWidth: 180,
      renderCell: (params) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <Store size={16} color="#0F52BA" />
          <Typography variant="body2" sx={{ fontWeight: 600 }}>
            {params.value as string}
          </Typography>
        </Box>
      ),
    },
    { field: 'category', headerName: 'Category', flex: 1, minWidth: 140 },
    {
      field: 'city',
      headerName: 'City',
      flex: 1,
      minWidth: 120,
      valueGetter: (_, row) => `${row.city || ''}, ${row.state || ''}`,
    },
    {
      field: 'verification_status',
      headerName: 'Queue Status',
      width: 140,
      renderCell: (params) => <StatusBadge status={params.value as string} />,
    },
    {
      field: 'created_at',
      headerName: 'Submitted At',
      flex: 1,
      minWidth: 160,
      valueFormatter: (value) => (value ? new Date(value as string).toLocaleString() : 'N/A'),
    },
    {
      field: 'actions',
      headerName: 'Triage Actions',
      width: 240,
      sortable: false,
      renderCell: (params) => {
        const item = params.row as ShopItem;
        return (
          <Box sx={{ display: 'flex', gap: 1 }}>
            <Button
              size="small"
              variant="text"
              startIcon={<Eye size={14} />}
              onClick={() => router.push(`/businesses/${item.id}`)}
            >
              Review
            </Button>
            <Button
              size="small"
              color="success"
              variant="contained"
              startIcon={<ShieldCheck size={14} />}
              onClick={() => setSelectedCase({ id: item.id, name: item.name, decision: 'VERIFY' })}
            >
              Approve
            </Button>
            <Button
              size="small"
              color="error"
              variant="outlined"
              startIcon={<ShieldAlert size={14} />}
              onClick={() => setSelectedCase({ id: item.id, name: item.name, decision: 'REJECT' })}
            >
              Reject
            </Button>
          </Box>
        );
      },
    },
  ];

  return (
    <Box>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Merchant Verification Center
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Pending storefront applications, physical verification triage, and identity validation.
        </Typography>
      </Box>

      <AdminDataGrid
        rows={(data?.items || []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        searchPlaceholder="Search pending verification queue..."
        searchValue={search}
        onSearchChange={setSearch}
        onRefresh={() => refetch()}
      />

      {selectedCase && (
        <ConfirmationDialog
          open={Boolean(selectedCase)}
          title={`${selectedCase.decision === 'VERIFY' ? 'Approve' : 'Reject'} Merchant Verification`}
          affectedItem={selectedCase.name}
          consequence={
            selectedCase.decision === 'VERIFY'
              ? 'Approving marks this business as verified across the platform, publishing its local catalog to active shopper search.'
              : 'Rejecting rejects this verification attempt and notifies the shopkeeper with the specified feedback reason.'
          }
          isDangerous={selectedCase.decision === 'REJECT'}
          requireReason
          isLoading={verificationMutation.isPending}
          onConfirm={handleDecision}
          onClose={() => setSelectedCase(null)}
        />
      )}
    </Box>
  );
}
