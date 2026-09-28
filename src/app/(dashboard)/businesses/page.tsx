'use client';

import React, { useState } from 'react';
import { useRouter } from 'next/navigation';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, Button, MenuItem, Select, FormControl, InputLabel } from '@mui/material';
import { ShieldCheck, ShieldAlert, Store, Eye } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { ShopItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';

export default function BusinessesPage() {
  const router = useRouter();
  const queryClient = useQueryClient();

  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [categoryFilter, setCategoryFilter] = useState('');

  // Action modal
  const [targetShop, setTargetShop] = useState<{ id: number; name: string; decision: 'VERIFY' | 'REJECT' | 'SUSPEND' | 'REACTIVATE' } | null>(null);

  const { data, isLoading, refetch } = useQuery<{ items: ShopItem[]; total: number }>({
    queryKey: ['admin', 'shops', { page: paginationModel.page, pageSize: paginationModel.pageSize, search, status: statusFilter, category: categoryFilter }],
    queryFn: () =>
      apiClient<{ items: ShopItem[]; total: number }>(API_ENDPOINTS.SHOPS.LIST, {
        params: {
          status: statusFilter || undefined,
          category: categoryFilter || undefined,
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
      queryClient.invalidateQueries({ queryKey: ['admin', 'shops'] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'dashboard', 'metrics'] });
    },
  });

  const handleConfirmVerification = async (reason: string) => {
    if (!targetShop) return;
    await verificationMutation.mutateAsync({
      shopId: targetShop.id,
      decision: targetShop.decision,
      reason,
    });
  };

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 70 },
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
    { field: 'category', headerName: 'Category', flex: 1, minWidth: 130 },
    {
      field: 'location',
      headerName: 'Location',
      flex: 1,
      minWidth: 130,
      valueGetter: (_, row) => `${row.city || ''}, ${row.state || ''}`,
    },
    {
      field: 'status',
      headerName: 'Status',
      width: 120,
      renderCell: (params) => <StatusBadge status={params.value as string} />,
    },
    {
      field: 'verification_status',
      headerName: 'Verification',
      width: 140,
      renderCell: (params) => <StatusBadge status={params.value as string} />,
    },
    {
      field: 'product_count',
      headerName: 'Products',
      width: 90,
      align: 'right',
      headerAlign: 'right',
    },
    {
      field: 'actions',
      headerName: 'Actions',
      width: 240,
      sortable: false,
      renderCell: (params) => {
        const shop = params.row as ShopItem;
        const isVerified = shop.verification_status === 'VERIFIED';
        const isSuspended = shop.status === 'SUSPENDED';

        return (
          <Box sx={{ display: 'flex', gap: 1 }}>
            <Button
              size="small"
              variant="text"
              startIcon={<Eye size={14} />}
              onClick={() => router.push(`/businesses/${shop.id}`)}
            >
              Detail
            </Button>

            {!isVerified && (
              <Button
                size="small"
                color="success"
                variant="outlined"
                startIcon={<ShieldCheck size={14} />}
                onClick={() => setTargetShop({ id: shop.id, name: shop.name, decision: 'VERIFY' })}
              >
                Verify
              </Button>
            )}

            {isSuspended ? (
              <Button
                size="small"
                color="primary"
                variant="outlined"
                onClick={() => setTargetShop({ id: shop.id, name: shop.name, decision: 'REACTIVATE' })}
              >
                Reactivate
              </Button>
            ) : (
              <Button
                size="small"
                color="error"
                variant="outlined"
                startIcon={<ShieldAlert size={14} />}
                onClick={() => setTargetShop({ id: shop.id, name: shop.name, decision: 'SUSPEND' })}
              >
                Suspend
              </Button>
            )}
          </Box>
        );
      },
    },
  ];

  return (
    <Box>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Business & Shop Management
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Audit physical retail shops, govern merchant listings, and verify storefront operations.
        </Typography>
      </Box>

      {/* Filters */}
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
            <MenuItem value="PENDING">Pending</MenuItem>
          </Select>
        </FormControl>

        <FormControl size="small" sx={{ minWidth: 160 }}>
          <InputLabel>Category</InputLabel>
          <Select
            value={categoryFilter}
            label="Category"
            onChange={(e) => setCategoryFilter(e.target.value)}
          >
            <MenuItem value="">All Categories</MenuItem>
            <MenuItem value="Pharmacy & Healthcare">Pharmacy & Healthcare</MenuItem>
            <MenuItem value="Beauty & Personal Care">Beauty & Personal Care</MenuItem>
            <MenuItem value="Hardware">Hardware</MenuItem>
            <MenuItem value="Automotive Parts & Tools">Automotive Parts & Tools</MenuItem>
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
        searchPlaceholder="Search shop by name or address..."
        searchValue={search}
        onSearchChange={setSearch}
        onRefresh={() => refetch()}
      />

      {targetShop && (
        <ConfirmationDialog
          open={Boolean(targetShop)}
          title={`${targetShop.decision} Shop - ${targetShop.name}`}
          affectedItem={targetShop.name}
          consequence={
            targetShop.decision === 'SUSPEND'
              ? 'This shop and its inventory will immediately disappear from customer discovery and search results.'
              : targetShop.decision === 'VERIFY'
              ? 'The shop will be publicly marked verified and eligible for high-confidence customer discovery.'
              : 'The operation will be recorded in the system audit trail.'
          }
          isDangerous={targetShop.decision === 'SUSPEND' || targetShop.decision === 'REJECT'}
          requireReason
          isLoading={verificationMutation.isPending}
          onConfirm={handleConfirmVerification}
          onClose={() => setTargetShop(null)}
        />
      )}
    </Box>
  );
}
