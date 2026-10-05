'use client';

import React, { use } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import {
  Box,
  Typography,
  Card,
  CardContent,
  Grid,
  Button,
  Tabs,
  Tab,
  Alert,
  CircularProgress,
  Divider,
} from '@mui/material';
import { ArrowLeft, Store, User, History, Package } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { InventoryRecordDetail, InventoryHistoryEntry } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';

function InventoryRecordContent({ params }: { params: Promise<{ id: string }> }) {
  const resolvedParams = use(params);
  const router = useRouter();
  const searchParams = useSearchParams();
  const recordId = resolvedParams.id;
  const [tabIndex, setTabIndex] = React.useState(0);
  const [paginationModel, setPaginationModel] = React.useState<GridPaginationModel>({
    page: 0,
    pageSize: 25,
  });
  const [historySearch, setHistorySearch] = React.useState('');

  const { data: record, isLoading, isError, error } = useQuery<InventoryRecordDetail>({
    queryKey: ['admin', 'inventory', 'record', recordId],
    queryFn: () => apiClient<InventoryRecordDetail>(API_ENDPOINTS.INVENTORY.RECORD_DETAIL(recordId)),
  });

  const { data: history, isLoading: historyLoading, refetch: refetchHistory } = useQuery<{
    items: InventoryHistoryEntry[];
    total: number;
  }>({
    queryKey: ['admin', 'inventory', 'history', recordId, paginationModel, historySearch],
    queryFn: () =>
      apiClient<{ items: InventoryHistoryEntry[]; total: number }>(
        API_ENDPOINTS.INVENTORY.RECORD_HISTORY(recordId),
        {
          params: {
            search: historySearch || undefined,
            limit: paginationModel.pageSize,
            offset: paginationModel.page * paginationModel.pageSize,
          },
        }
      ),
  });

  const historyColumns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    { field: 'change_type', headerName: 'Change Type', width: 160 },
    { field: 'old_value', headerName: 'Old Value', flex: 1 },
    { field: 'new_value', headerName: 'New Value', flex: 1 },
    { field: 'source', headerName: 'Source', width: 140 },
    { field: 'changed_by', headerName: 'Changed By', width: 160 },
    {
      field: 'created_at',
      headerName: 'Timestamp',
      flex: 1.2,
      valueFormatter: (value) => (value ? new Date(value as string).toLocaleString() : '—'),
    },
  ];

  if (isLoading) {
    return (
      <Box sx={{ display: 'flex', justifyContent: 'center', py: 8 }}>
        <CircularProgress />
      </Box>
    );
  }

  if (isError || !record) {
    return (
      <Box>
        <DrillDownBreadcrumbs
          items={[
            { label: 'Dashboard', href: '/dashboard' },
            { label: 'Inventory', href: '/inventory' },
            { label: `Record #${recordId}` },
          ]}
        />
        <Alert severity="error">
          Could not load inventory record #{recordId}:{' '}
          {error instanceof Error ? error.message : 'Unknown error'}
        </Alert>
      </Box>
    );
  }

  const cameFromShop = searchParams.get('from') === 'shop';

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: '/dashboard' },
          { label: 'Inventory', href: '/inventory' },
          { label: record.shop_name, href: cameFromShop ? `/businesses/${record.shop_id}` : '/inventory' },
          { label: `Record #${record.shop_product_id}` },
        ]}
      />

      <Button startIcon={<ArrowLeft size={16} />} onClick={() => router.back()} sx={{ mb: 2 }}>
        Back
      </Button>

      {/* Record Header */}
      <Card sx={{ mb: 3 }}>
        <CardContent sx={{ p: 3 }}>
          <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: 2 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
              <Box sx={{ p: 1.2, backgroundColor: '#FFFBEB', borderRadius: 2, color: '#F59E0B' }}>
                <Package size={26} />
              </Box>
              <Box>
                <Typography variant="h5" sx={{ fontWeight: 700 }}>
                  {record.product_name}
                </Typography>
                <Typography variant="body2" color="text.secondary">
                  Inventory Record #{record.shop_product_id} · Shop: {record.shop_name}
                </Typography>
              </Box>
            </Box>
            <Box sx={{ display: 'flex', gap: 1 }}>
              <StatusBadge status={record.stock_status} size="medium" />
              <StatusBadge status={record.freshness_status || 'STALE'} size="medium" />
            </Box>
          </Box>

          <Divider sx={{ my: 2.5 }} />

          {/* Drill-down pivot buttons: Record → Shop → Shopkeeper */}
          <Box sx={{ display: 'flex', gap: 1.5, flexWrap: 'wrap' }}>
            <Button
              variant="outlined"
              size="small"
              startIcon={<Store size={15} />}
              onClick={() => router.push(`/businesses/${record.shop_id}?from=inventory-record`)}
            >
              View Shop: {record.shop_name}
            </Button>
            <Button
              variant="outlined"
              size="small"
              startIcon={<User size={15} />}
              onClick={() => router.push(`/shopkeepers?highlight=${record.owner_id}`)}
            >
              Shopkeeper {record.owner_name ? `: ${record.owner_name}` : `#${record.owner_id}`}
            </Button>
            <Button
              variant="outlined"
              size="small"
              startIcon={<History size={15} />}
              onClick={() => setTabIndex(1)}
            >
              Inventory History
            </Button>
          </Box>
        </CardContent>
      </Card>

      <Tabs value={tabIndex} onChange={(_, val) => setTabIndex(val)} sx={{ mb: 2 }}>
        <Tab label="Record Details" />
        <Tab label="Inventory History" />
      </Tabs>

      {/* Tab 0: Record details */}
      {tabIndex === 0 && (
        <Grid container spacing={3}>
          <Grid item xs={12} md={6}>
            <Card>
              <CardContent sx={{ p: 3 }}>
                <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 2 }}>
                  Stock Information
                </Typography>
                <DetailRow label="Quantity" value={record.quantity ?? '—'} />
                <DetailRow label="Price" value={record.price != null ? `₹${record.price}` : '—'} />
                <DetailRow label="MRP" value={record.mrp != null ? `₹${record.mrp}` : '—'} />
                <DetailRow label="Availability" value={record.availability || '—'} />
                <DetailRow label="Stale Hours" value={record.stale_hours ?? '—'} />
                <DetailRow
                  label="Last Updated"
                  value={record.last_updated ? new Date(record.last_updated).toLocaleString() : '—'}
                />
              </CardContent>
            </Card>
          </Grid>
          <Grid item xs={12} md={6}>
            <Card>
              <CardContent sx={{ p: 3 }}>
                <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 2 }}>
                  Sync & Ownership
                </Typography>
                <DetailRow label="Shop" value={record.shop_name} />
                <DetailRow label="Shop ID" value={`#${record.shop_id}`} />
                <DetailRow label="Shopkeeper" value={record.owner_name || `#${record.owner_id}`} />
                <DetailRow label="Owner Phone" value={record.owner_phone || '—'} />
                <DetailRow label="Sync Source" value={record.sync_source || '—'} />
                <DetailRow label="Sync Status" value={record.sync_status || '—'} />
                <DetailRow label="Sync Error" value={record.sync_error || 'None'} />
              </CardContent>
            </Card>
          </Grid>
        </Grid>
      )}

      {/* Tab 1: History */}
      {tabIndex === 1 && (
        <AdminDataGrid
          rows={(history?.items || []) as unknown as Record<string, unknown>[]}
          columns={historyColumns}
          totalRows={history?.total ?? 0}
          paginationModel={paginationModel}
          onPaginationModelChange={setPaginationModel}
          loading={historyLoading}
          searchPlaceholder="Search history entries..."
          searchValue={historySearch}
          onSearchChange={setHistorySearch}
          onRefresh={() => refetchHistory()}
        />
      )}
    </Box>
  );
}

function DetailRow({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <Box sx={{ display: 'flex', justifyContent: 'space-between', py: 0.75, borderBottom: '1px solid #F1F5F9' }}>
      <Typography variant="body2" color="text.secondary">
        {label}
      </Typography>
      <Typography variant="body2" sx={{ fontWeight: 600, textAlign: 'right' }}>
        {value}
      </Typography>
    </Box>
  );
}

export default function InventoryRecordPage(props: { params: Promise<{ id: string }> }) {
  return (
    <React.Suspense fallback={null}>
      <InventoryRecordContent {...props} />
    </React.Suspense>
  );
}
