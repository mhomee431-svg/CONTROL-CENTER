'use client';

import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, Button } from '@mui/material';
import { Check, X, HelpCircle, Package } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';

interface ApprovalItem {
  id: number;
  product_name: string;
  shop_name: string;
  category_name?: string;
  proposed_price?: number;
  created_at: string;
  status: string;
}

export default function ProductApprovalsPage() {
  const queryClient = useQueryClient();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [selectedListing, setSelectedListing] = useState<{ id: number; name: string; decision: 'APPROVE' | 'REJECT' | 'NEEDS_INFO' } | null>(null);

  const { data, isLoading, refetch } = useQuery<{ items: ApprovalItem[]; total: number }>({
    queryKey: ['admin', 'product-approvals', { page: paginationModel.page, pageSize: paginationModel.pageSize }],
    queryFn: () =>
      apiClient<{ items: ApprovalItem[]; total: number }>(API_ENDPOINTS.PRODUCTS.APPROVALS, {
        params: {
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
  });

  const reviewMutation = useMutation({
    mutationFn: ({ listingId, decision, reason }: { listingId: number; decision: string; reason: string }) =>
      apiClient(API_ENDPOINTS.PRODUCTS.REVIEW_LISTING(listingId), {
        method: 'POST',
        params: { decision, review_notes: reason },
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin', 'product-approvals'] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'dashboard', 'metrics'] });
    },
  });

  const handleReview = async (reason: string) => {
    if (!selectedListing) return;
    await reviewMutation.mutateAsync({
      listingId: selectedListing.id,
      decision: selectedListing.decision,
      reason,
    });
  };

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'Listing ID', width: 90 },
    {
      field: 'product_name',
      headerName: 'Proposed Product',
      flex: 1.5,
      minWidth: 180,
      renderCell: (params) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <Package size={16} color="#0F52BA" />
          <Typography variant="body2" sx={{ fontWeight: 600 }}>
            {params.value as string}
          </Typography>
        </Box>
      ),
    },
    { field: 'shop_name', headerName: 'Shopkeeper Store', flex: 1, minWidth: 150 },
    { field: 'category_name', headerName: 'Category', flex: 1, minWidth: 130 },
    {
      field: 'proposed_price',
      headerName: 'Proposed Price',
      width: 130,
      align: 'right',
      headerAlign: 'right',
      valueFormatter: (value) => (value ? `₹${Number(value).toFixed(2)}` : 'N/A'),
    },
    {
      field: 'status',
      headerName: 'Status',
      width: 130,
      renderCell: (params) => <StatusBadge status={params.value as string} />,
    },
    {
      field: 'actions',
      headerName: 'Review Actions',
      width: 280,
      sortable: false,
      renderCell: (params) => {
        const item = params.row as ApprovalItem;
        return (
          <Box sx={{ display: 'flex', gap: 1 }}>
            <Button
              size="small"
              color="success"
              variant="contained"
              startIcon={<Check size={14} />}
              onClick={() => setSelectedListing({ id: item.id, name: item.product_name, decision: 'APPROVE' })}
            >
              Approve
            </Button>
            <Button
              size="small"
              color="warning"
              variant="outlined"
              startIcon={<HelpCircle size={14} />}
              onClick={() => setSelectedListing({ id: item.id, name: item.product_name, decision: 'NEEDS_INFO' })}
            >
              Needs Info
            </Button>
            <Button
              size="small"
              color="error"
              variant="outlined"
              startIcon={<X size={14} />}
              onClick={() => setSelectedListing({ id: item.id, name: item.product_name, decision: 'REJECT' })}
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
          Product Approval Queue
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Review shopkeeper-submitted custom catalog items before they go live on the platform.
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

      {selectedListing && (
        <ConfirmationDialog
          open={Boolean(selectedListing)}
          title={`${selectedListing.decision} Product Listing`}
          affectedItem={selectedListing.name}
          consequence={
            selectedListing.decision === 'APPROVE'
              ? 'This listing will be approved and immediately enabled for shopper discovery.'
              : selectedListing.decision === 'NEEDS_INFO'
              ? 'The shopkeeper will be asked to supply more specific barcodes or images.'
              : 'This listing will be rejected and suppressed.'
          }
          isDangerous={selectedListing.decision === 'REJECT'}
          requireReason
          isLoading={reviewMutation.isPending}
          onConfirm={handleReview}
          onClose={() => setSelectedListing(null)}
        />
      )}
    </Box>
  );
}
