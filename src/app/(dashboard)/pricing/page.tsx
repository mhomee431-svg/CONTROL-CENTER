'use client';

import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, Card, CardContent, Grid } from '@mui/material';
import { DollarSign, AlertTriangle } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { StaleInventoryItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';

interface PricingAnomaly extends Partial<StaleInventoryItem> {
  id?: number;
  shop_product_id: number;
  product_name: string;
  shop_name: string;
  price?: number | null;
  mrp?: number | null;
}

export default function PricingPage() {
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [search, setSearch] = useState('');

  const { data, isLoading, isError, refetch } = useQuery<{ items: PricingAnomaly[]; total: number }>({
    queryKey: ['admin', 'pricing-anomalies', { page: paginationModel.page, pageSize: paginationModel.pageSize, search }],
    queryFn: () =>
      apiClient<{ items: PricingAnomaly[]; total: number }>(API_ENDPOINTS.INVENTORY.MISSING_PRICES, {
        params: {
          search: search || undefined,
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
  });

  const columns: GridColDef[] = [
    { field: 'shop_product_id', headerName: 'Record ID', width: 100 },
    { field: 'product_name', headerName: 'Product', flex: 1.5, minWidth: 180 },
    { field: 'shop_name', headerName: 'Shop', flex: 1.2, minWidth: 150 },
    {
      field: 'price',
      headerName: 'Listed Price',
      width: 130,
      align: 'right',
      valueFormatter: (value) => (value != null ? `₹${value}` : 'MISSING'),
    },
    {
      field: 'mrp',
      headerName: 'MRP',
      width: 120,
      align: 'right',
      valueFormatter: (value) => (value != null ? `₹${value}` : '—'),
    },
    {
      field: 'stock_status',
      headerName: 'Stock',
      width: 120,
      renderCell: (params) => <StatusBadge status={(params.value as string) || 'UNKNOWN'} />,
    },
  ];

  return (
    <Box>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Pricing Integrity Control Center
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Investigate missing prices, price anomalies, and MRP violations across shop inventories.
        </Typography>
      </Box>

      <Grid container spacing={2.5} sx={{ mb: 3 }}>
        <Grid item xs={12} sm={6} md={4}>
          <Card sx={{ borderLeft: '4px solid #F59E0B' }}>
            <CardContent sx={{ p: 2 }}>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <Box>
                  <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 600 }}>
                    MISSING PRICES
                  </Typography>
                  <Typography variant="h5" sx={{ fontWeight: 700, mt: 0.5 }}>
                    {data?.total ?? 0}
                  </Typography>
                </Box>
                <AlertTriangle size={22} color="#F59E0B" />
              </Box>
            </CardContent>
          </Card>
        </Grid>
        <Grid item xs={12} sm={6} md={4}>
          <Card sx={{ borderLeft: '4px solid #0F52BA' }}>
            <CardContent sx={{ p: 2 }}>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <Box>
                  <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 600 }}>
                    PRICING REVIEW QUEUE
                  </Typography>
                  <Typography variant="h5" sx={{ fontWeight: 700, mt: 0.5 }}>
                    {isLoading ? '...' : `${data?.items?.length ?? 0} records`}
                  </Typography>
                </Box>
                <DollarSign size={22} color="#0F52BA" />
              </Box>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      <AdminDataGrid
        rows={(data?.items || []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        searchPlaceholder="Search pricing records..."
        searchValue={search}
        onSearchChange={setSearch}
        onRefresh={() => refetch()}
        error={isError}
      />
    </Box>
  );
}
