'use client';

import React, { useState, useEffect } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import {
  Box,
  Typography,
  Card,
  CardContent,
  Grid,
  Tabs,
  Tab,
} from '@mui/material';
import { Warehouse, Clock, AlertTriangle, AlertCircle } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { StaleInventoryItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';

function InventoryContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [tabIndex, setTabIndex] = useState(0);
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });

  // Deep-link support: dashboard "Stale Inventory" drill-down lands on ?filter=stale
  useEffect(() => {
    const filter = searchParams.get('filter');
    if (filter === 'stale') setTabIndex(0);
    else if (filter === 'missing-prices') setTabIndex(1);
    else if (filter === 'anomalies') setTabIndex(2);
    else if (filter === 'sync-failures') setTabIndex(3);
  }, [searchParams]);

  // Summary Metrics
  const { data: summary } = useQuery<{
    fresh_count: number;
    recent_count: number;
    stale_count: number;
    unknown_count: number;
    missing_prices_count: number;
    sync_failures_count: number;
  }>({
    queryKey: ['admin', 'inventory-summary'],
    queryFn: () => apiClient(API_ENDPOINTS.INVENTORY.SUMMARY),
  });

  // Table Data based on active tab
  const getEndpoint = () => {
    switch (tabIndex) {
      case 1:
        return API_ENDPOINTS.INVENTORY.MISSING_PRICES;
      case 2:
        return API_ENDPOINTS.INVENTORY.ANOMALIES;
      case 3:
        return API_ENDPOINTS.INVENTORY.SYNC_FAILURES;
      default:
        return API_ENDPOINTS.INVENTORY.STALE;
    }
  };

  const { data, isLoading, refetch } = useQuery<{ items: StaleInventoryItem[]; total: number }>({
    queryKey: ['admin', 'inventory-list', tabIndex, { page: paginationModel.page, pageSize: paginationModel.pageSize }],
    queryFn: () =>
      apiClient<{ items: StaleInventoryItem[]; total: number }>(getEndpoint(), {
        params: {
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
  });

  const columns: GridColDef[] = [
    { field: 'shop_product_id', headerName: 'ID', width: 80 },
    {
      field: 'product_name',
      headerName: 'Product',
      flex: 1.5,
      minWidth: 180,
      renderCell: (params) => (
        <Typography variant="body2" sx={{ fontWeight: 600 }}>
          {params.value as string}
        </Typography>
      ),
    },
    { field: 'shop_name', headerName: 'Store Location', flex: 1.2, minWidth: 150 },
    {
      field: 'quantity',
      headerName: 'Stock Qty',
      width: 100,
      align: 'right',
      headerAlign: 'right',
    },
    {
      field: 'stock_status',
      headerName: 'Stock Status',
      width: 130,
      renderCell: (params) => <StatusBadge status={params.value as string} />,
    },
    {
      field: 'freshness_status',
      headerName: 'Freshness',
      width: 130,
      renderCell: (params) => <StatusBadge status={(params.value as string) || 'STALE'} />,
    },
    {
      field: 'last_updated',
      headerName: 'Last Synced',
      flex: 1,
      minWidth: 160,
      valueFormatter: (value) => (value ? new Date(value as string).toLocaleString() : 'N/A'),
    },
  ];

  return (
    <Box>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Inventory Freshness & Control Center
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Section 36 & 37: Monitor store inventory staleness, missing pricing anomalies, and POS sync integrity.
        </Typography>
      </Box>

      {/* Freshness Summary Cards */}
      <Grid container spacing={2.5} sx={{ mb: 3 }}>
        <Grid item xs={12} sm={6} md={3}>
          <Card sx={{ borderLeft: '4px solid #10B981' }}>
            <CardContent sx={{ p: 2 }}>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <Box>
                  <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 600 }}>
                    FRESH RECORDS (&lt;24H)
                  </Typography>
                  <Typography variant="h5" sx={{ fontWeight: 700, mt: 0.5 }}>
                    {summary?.fresh_count ?? 0}
                  </Typography>
                </Box>
                <Warehouse size={22} color="#10B981" />
              </Box>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card sx={{ borderLeft: '4px solid #EF4444' }}>
            <CardContent sx={{ p: 2 }}>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <Box>
                  <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 600 }}>
                    STALE RECORDS (&gt;48H)
                  </Typography>
                  <Typography variant="h5" sx={{ fontWeight: 700, mt: 0.5 }}>
                    {summary?.stale_count ?? 0}
                  </Typography>
                </Box>
                <Clock size={22} color="#EF4444" />
              </Box>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card sx={{ borderLeft: '4px solid #F59E0B' }}>
            <CardContent sx={{ p: 2 }}>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <Box>
                  <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 600 }}>
                    MISSING PRICES
                  </Typography>
                  <Typography variant="h5" sx={{ fontWeight: 700, mt: 0.5 }}>
                    {summary?.missing_prices_count ?? 0}
                  </Typography>
                </Box>
                <AlertTriangle size={22} color="#F59E0B" />
              </Box>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card sx={{ borderLeft: '4px solid #6366F1' }}>
            <CardContent sx={{ p: 2 }}>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <Box>
                  <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 600 }}>
                    SYNC FAILURES
                  </Typography>
                  <Typography variant="h5" sx={{ fontWeight: 700, mt: 0.5 }}>
                    {summary?.sync_failures_count ?? 0}
                  </Typography>
                </Box>
                <AlertCircle size={22} color="#6366F1" />
              </Box>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      {/* Tabs */}
      <Tabs value={tabIndex} onChange={(_, val) => setTabIndex(val)} sx={{ mb: 2 }}>
        <Tab label="Stale Inventory" />
        <Tab label="Missing Prices" />
        <Tab label="Availability Anomalies" />
        <Tab label="Sync Failures" />
      </Tabs>

      <AdminDataGrid
        rows={(data?.items || []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        onRefresh={() => refetch()}
        onRowClick={(params) => router.push(`/inventory/${params.row.shop_product_id ?? params.id}`)}
      />

      {/* Drill-down hint: every row is an investigation entry point */}
      <Typography variant="caption" color="text.secondary" sx={{ mt: 1.5, display: 'block' }}>
        Click any record to open its full Inventory Record — history, shop, and shopkeeper drill-down.
      </Typography>
    </Box>
  );
}

export default function InventoryPage() {
  return (
    <React.Suspense fallback={null}>
      <InventoryContent />
    </React.Suspense>
  );
}
