'use client';

import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, Alert } from '@mui/material';
import { useRouter } from 'next/navigation';
import { Plug, AlertTriangle } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { PosIntegrationItem, providerDisplayName } from '@/core/types/pos';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';
import {
  declaredCapabilities,
  formatSyncAge,
  isStale,
  normalizePosStatus,
  resultFor,
} from '@/core/pos/connection';

const STATUS_FILTERS = [
  { value: 'all', label: 'All' },
  { value: 'CONNECTED', label: 'Connected' },
  { value: 'DISCONNECTED', label: 'Disconnected' },
  { value: 'SYNCING', label: 'Syncing' },
  { value: 'SYNC_FAILED', label: 'Failed' },
] as const;

export default function PosPage() {
  const router = useRouter();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [statusFilter, setStatusFilter] = useState<string>('all');

  const { data, isLoading, refetch, isError } = useQuery<{ items: PosIntegrationItem[]; total: number }>({
    queryKey: ['admin', 'pos', paginationModel, statusFilter],
    queryFn: () =>
      apiClient<{ items: PosIntegrationItem[]; total: number }>(API_ENDPOINTS.POS.LIST, {
        params: {
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
          ...(statusFilter !== 'all' ? { status: statusFilter } : {}),
        },
      }),
    retry: false,
    // A syncing integration changes state on its own — keep the grid live.
    refetchInterval: (query) => {
      const items = query.state.data?.items as PosIntegrationItem[] | undefined;
      return items?.some((i) => normalizePosStatus(i.status) === 'SYNCING') ? 5000 : false;
    },
  });

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    {
      field: 'shop_name',
      headerName: 'Shop',
      flex: 1.4,
      minWidth: 180,
      valueGetter: (_, row) => {
        const item = row as PosIntegrationItem;
        return item.shop_name || (item.shop_id ? `Shop #${item.shop_id}` : 'Unassigned shop');
      },
      renderCell: (params) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <Plug size={16} color="#8B5CF6" />
          <Typography variant="body2" sx={{ fontWeight: 600 }}>
            {params.value as string}
          </Typography>
        </Box>
      ),
    },
    {
      field: 'provider_code',
      headerName: 'Provider',
      flex: 1,
      minWidth: 150,
      // Opaque backend label — never a hardcoded vendor list.
      valueGetter: (_, row) => providerDisplayName(row as PosIntegrationItem),
    },
    {
      field: 'capabilities',
      headerName: 'Capabilities',
      flex: 1.3,
      minWidth: 200,
      sortable: false,
      valueGetter: (_, row) => declaredCapabilities(row as PosIntegrationItem).join(', ') || '—',
    },
    {
      field: 'status',
      headerName: 'Status',
      width: 145,
      renderCell: (params) => <StatusBadge status={(params.value as string) || 'DISCONNECTED'} />,
    },
    {
      field: 'products_synced',
      headerName: 'Products Synced',
      width: 140,
      align: 'right',
      headerAlign: 'right',
      valueGetter: (_, row) => resultFor('PRODUCTS', row as PosIntegrationItem)?.records_synced ?? '—',
    },
    {
      field: 'inventory_synced',
      headerName: 'Inventory Synced',
      width: 145,
      align: 'right',
      headerAlign: 'right',
      valueGetter: (_, row) => resultFor('INVENTORY', row as PosIntegrationItem)?.records_synced ?? '—',
    },
    {
      field: 'last_sync_at',
      headerName: 'Last Sync',
      flex: 1.2,
      minWidth: 175,
      valueGetter: (_, row) => {
        const item = row as PosIntegrationItem;
        const age = formatSyncAge(item);
        return isStale(item) && normalizePosStatus(item.status) !== 'SYNCING'
          ? `${age} · stale`
          : age;
      },
      renderCell: (params) => {
        const item = params.row as PosIntegrationItem;
        const stale = isStale(item) && normalizePosStatus(item.status) !== 'SYNCING';
        return (
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
            {stale && <AlertTriangle size={13} color="#F59E0B" />}
            <Typography variant="body2" color={stale ? 'warning.main' : 'text.primary'}>
              {(params.value as string) || 'Never'}
            </Typography>
          </Box>
        );
      },
    },
  ];

  const items = data?.items || [];
  const counts = {
    connected: items.filter((i) => normalizePosStatus(i.status) === 'CONNECTED').length,
    disconnected: items.filter((i) => normalizePosStatus(i.status) === 'DISCONNECTED').length,
    syncing: items.filter((i) => normalizePosStatus(i.status) === 'SYNCING').length,
    failed: items.filter((i) => normalizePosStatus(i.status) === 'SYNC_FAILED').length,
  };

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'POS Control Center' },
        ]}
      />
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          POS Control Center
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Monitor point-of-sale integrations — connection health, sync state and catalog/inventory throughput.
        </Typography>
      </Box>

      <Alert severity="info" sx={{ mb: 2 }}>
        This console is provider-neutral: integrations are described by the capabilities they declare, not by any
        specific vendor. Adding a new POS provider requires no changes here.
      </Alert>

      {isError && (
        <Alert severity="warning" sx={{ mb: 2 }}>
          The POS integrations endpoint is unavailable on this backend, or you lack the inventory capability.
        </Alert>
      )}

      {/* Summary rail across the four documented states */}
      <Box sx={{ display: 'flex', gap: 1, mb: 2, flexWrap: 'wrap' }}>
        <SummaryTile label="Connected" value={counts.connected} color="#10B981" />
        <SummaryTile label="Disconnected" value={counts.disconnected} color="#EF4444" />
        <SummaryTile label="Syncing" value={counts.syncing} color="#F59E0B" />
        <SummaryTile label="Sync Failed" value={counts.failed} color="#EF4444" />
      </Box>

      <Box sx={{ display: 'flex', gap: 1, mb: 2, flexWrap: 'wrap' }}>
        {STATUS_FILTERS.map((filter) => (
          <Box
            key={filter.value}
            component="button"
            type="button"
            onClick={() => {
              setStatusFilter(filter.value);
              setPaginationModel((p) => ({ ...p, page: 0 }));
            }}
            sx={{
              px: 1.5,
              py: 0.5,
              borderRadius: '20px',
              fontSize: '0.75rem',
              fontWeight: 600,
              fontFamily: 'inherit',
              cursor: 'pointer',
              border: '1px solid',
              borderColor: statusFilter === filter.value ? 'primary.main' : '#CBD5E1',
              backgroundColor: statusFilter === filter.value ? '#EFF6FF' : '#FFFFFF',
              color: statusFilter === filter.value ? 'primary.main' : '#475569',
              '&:hover': { borderColor: 'primary.main' },
            }}
          >
            {filter.label}
          </Box>
        ))}
      </Box>

      <AdminDataGrid
        rows={items as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? items.length}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        error={isError}
        errorMessage="POS integrations could not be loaded. The request failed — retry, and escalate if it keeps failing."
        searchPlaceholder="Search POS integrations..."
        onRefresh={() => refetch()}
        onRowClick={(params) => router.push(ROUTES.POS_DETAIL(params.row.id as number))}
      />
    </Box>
  );
}

const SummaryTile: React.FC<{ label: string; value: number; color: string }> = ({ label, value, color }) => (
  <Box
    sx={{
      px: 2,
      py: 1,
      borderRadius: 1.5,
      border: '1px solid #E2E8F0',
      backgroundColor: '#FFFFFF',
      minWidth: 120,
    }}
  >
    <Typography variant="caption" color="text.secondary">
      {label}
    </Typography>
    <Typography variant="h6" sx={{ fontWeight: 700, color, lineHeight: 1.2 }}>
      {value}
    </Typography>
  </Box>
);
