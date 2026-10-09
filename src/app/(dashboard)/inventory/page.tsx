'use client';

import React, { useEffect, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import {
  Box,
  Typography,
  Card,
  CardContent,
  CardActionArea,
  Grid,
  Tabs,
  Tab,
  Alert,
} from '@mui/material';
import { Clock, TrendingUp, AlertTriangle, HelpCircle, Lock } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { fetchList, ListResult } from '@/core/api/fetchList';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { InventorySummary, StaleInventoryItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { ROUTES } from '@/core/routes/routes';
import { useAuth } from '@/core/auth/AuthContext';
import { CAPABILITIES, hasPermission } from '@/core/permissions/permissions';
import { classifyFreshness, percentOf } from '@/core/inventory/freshness';

// ---------------------------------------------------------------------------
// Section 36 & 37 — Inventory Control Center / Inventory Freshness Monitoring
// ---------------------------------------------------------------------------
// Sections:  All Inventory | In Stock | Low Stock | Out of Stock | Unknown |
//            Stale | Recently Updated | Failed Updates — one backend route
//            (GET /admin/inventory?section=...), eight section views.
//
// Table:     Shop | Product | Quantity (where authorized) | Availability |
//            Source | Freshness | Last Updated
//
// Dashboard: Fresh % | Recent % | Stale % | Unknown % — backend-computed
//            freshness buckets. Clicking a KPI jumps to its section; clicking
//            a row drills shop -> product -> last update -> source via the
//            inventory record detail.
// ---------------------------------------------------------------------------

/** The eight sections, in tab order. `id` is the backend `section` param. */
const SECTIONS = [
  { id: 'all', label: 'All Inventory' },
  { id: 'in-stock', label: 'In Stock' },
  { id: 'low-stock', label: 'Low Stock' },
  { id: 'out-of-stock', label: 'Out of Stock' },
  { id: 'unknown', label: 'Unknown' },
  { id: 'stale', label: 'Stale' },
  { id: 'recently-updated', label: 'Recently Updated' },
  { id: 'failed', label: 'Failed Updates' },
] as const;

type SectionId = (typeof SECTIONS)[number]['id'];

/** One grid row: the backend record plus the DataGrid row id. */
type InventoryRow = StaleInventoryItem & { id: number };

function InventoryContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const { adminRole } = useAuth();

  // "Quantity where authorized": exact counts are operationally sensitive, so
  // they render only for operators who hold inventory.update; everyone else
  // sees a masked cell (same policy pattern as the customer PII columns).
  const canSeeQuantity = hasPermission(adminRole, CAPABILITIES.INVENTORY_UPDATE);

  const [sectionIndex, setSectionIndex] = useState(0);
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [search, setSearch] = useState('');
  const section: SectionId = SECTIONS[sectionIndex].id;

  // Deep-link support: the dashboard's "Stale Inventory" tile lands on
  // ?filter=stale; the legacy filters map onto the closest new section.
  useEffect(() => {
    const filter = searchParams.get('filter');
    if (filter === 'stale') setSectionIndex(5);
    else if (filter === 'sync-failures') setSectionIndex(7);
    else if (filter === 'missing-prices' || filter === 'anomalies') setSectionIndex(0);
  }, [searchParams]);

  // Freshness dashboard buckets. A backend that does not publish them leaves
  // the counts undefined and the tiles render '—' rather than a fake 0%.
  const { data: summary } = useQuery<InventorySummary>({
    queryKey: ['admin', 'inventory-summary'],
    queryFn: () => apiClient<InventorySummary>(API_ENDPOINTS.INVENTORY.SUMMARY),
  });

  // One route, eight sections. fetchList reports an unpublished route as
  // `unavailable` rather than an empty grid, so a deployment lag reads as
  // "not published" instead of "no inventory records".
  const { data, isLoading, isError, refetch } = useQuery<ListResult<InventoryRow>>({
    queryKey: ['admin', 'inventory', 'list', section, paginationModel, search],
    queryFn: () =>
      fetchList<InventoryRow>(API_ENDPOINTS.INVENTORY.LIST, {
        params: {
          section,
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
          search: search || undefined,
        },
      }),
  });

  const rows: InventoryRow[] = (data?.items ?? []).map((r) => ({
    ...r,
    id: r.shop_product_id,
  }));

  // Fresh % | Recent % | Stale % | Unknown % over the platform total.
  const pct = (count?: number): string =>
    summary && count != null && summary.total_records > 0
      ? `${percentOf(count, summary.total_records)}%`
      : '—';
  const columns: GridColDef[] = [
    {
      field: 'shop_name',
      headerName: 'Shop',
      flex: 1.2,
      minWidth: 150,
      renderCell: (params) => (
        <Box sx={{ width: '100%', minWidth: 0 }}>
          <Typography
            variant="body2"
            sx={{ fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}
          >
            {params.value as string}
          </Typography>
          <Typography variant="caption" color="text.secondary" sx={{ display: 'block' }}>
            #{params.row.shop_id}
          </Typography>
        </Box>
      ),
    },
    {
      field: 'product_name',
      headerName: 'Product',
      flex: 1.4,
      minWidth: 160,
      renderCell: (params) => (
        <Typography
          variant="body2"
          sx={{ fontWeight: 500, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}
        >
          {params.value as string}
        </Typography>
      ),
    },
    {
      field: 'quantity',
      headerName: 'Quantity',
      width: 110,
      align: 'right',
      headerAlign: 'right',
      // "Quantity where authorized" — masked without inventory.update.
      renderCell: (params) =>
        canSeeQuantity ? (
          <Typography variant="body2" sx={{ fontWeight: 700 }}>
            {params.value as number}
          </Typography>
        ) : (
          <Typography
            variant="body2"
            color="text.secondary"
            title="Quantity hidden for your role"
            sx={{ display: 'inline-flex', alignItems: 'center', gap: 0.5 }}
          >
            <Lock size={12} />
            •••
          </Typography>
        ),
    },
    {
      field: 'availability',
      headerName: 'Availability',
      width: 140,
      // Falls back to stock status when the sync stored no availability.
      renderCell: (params) => (
        <StatusBadge
          status={(params.value as string) || (params.row.stock_status as string) || 'UNKNOWN'}
        />
      ),
    },
    {
      field: 'last_updated_source',
      headerName: 'Source',
      width: 140,
      renderCell: (params) => {
        const row = params.row as InventoryRow;
        const source = (params.value as string) || row.sync_source;
        return <Typography variant="body2" color="text.secondary">{source || '—'}</Typography>;
      },
    },
    {
      field: 'freshness_status',
      headerName: 'Freshness',
      width: 130,
      // Derived from the timestamp so this cell always agrees with the
      // section filters and the dashboard buckets — the stored
      // freshness_status column can lag behind reality.
      renderCell: (params) => (
        <StatusBadge status={classifyFreshness((params.row as InventoryRow).last_updated)} />
      ),
    },
    {
      field: 'last_updated',
      headerName: 'Last Updated',
      width: 170,
      valueFormatter: (value) => (value ? new Date(value as string).toLocaleString() : '—'),
    },
  ];
  return (
    <Box>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Inventory Control Center
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Inventory freshness monitoring — Fresh &lt;{summary?.fresh_after_hours ?? 24}h · Recent{' '}
          {summary?.fresh_after_hours ?? 24}–{summary?.stale_after_hours ?? 72}h · Stale &gt;
          {summary?.stale_after_hours ?? 72}h · Unknown = never updated.
        </Typography>
      </Box>

      {/* Inventory freshness dashboard: Fresh % | Recent % | Stale % | Unknown % */}
      <Grid container spacing={2.5} sx={{ mb: 3 }}>
        <Grid item xs={12} sm={6} md={3}>
          <Card sx={{ borderLeft: '4px solid #10B981' }}>
            <CardActionArea onClick={() => setSectionIndex(6)}>
              <CardContent sx={{ p: 2 }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <Box>
                    <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 600 }}>
                      FRESH %
                    </Typography>
                    <Typography variant="h5" sx={{ fontWeight: 700, mt: 0.5 }}>
                      {pct(summary?.fresh_count)}
                    </Typography>
                    <Typography variant="caption" color="text.secondary">
                      {summary?.fresh_count != null ? `${summary.fresh_count.toLocaleString()} records` : ''}
                    </Typography>
                  </Box>
                  <TrendingUp size={22} color="#10B981" />
                </Box>
              </CardContent>
            </CardActionArea>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card sx={{ borderLeft: '4px solid #3B82F6' }}>
            <CardActionArea onClick={() => setSectionIndex(6)}>
              <CardContent sx={{ p: 2 }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <Box>
                    <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 600 }}>
                      RECENT %
                    </Typography>
                    <Typography variant="h5" sx={{ fontWeight: 700, mt: 0.5 }}>
                      {pct(summary?.recent_count)}
                    </Typography>
                    <Typography variant="caption" color="text.secondary">
                      {summary?.recent_count != null ? `${summary.recent_count.toLocaleString()} records` : ''}
                    </Typography>
                  </Box>
                  <Clock size={22} color="#3B82F6" />
                </Box>
              </CardContent>
            </CardActionArea>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card sx={{ borderLeft: '4px solid #EF4444' }}>
            <CardActionArea onClick={() => setSectionIndex(5)}>
              <CardContent sx={{ p: 2 }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <Box>
                    <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 600 }}>
                      STALE %
                    </Typography>
                    <Typography variant="h5" sx={{ fontWeight: 700, mt: 0.5 }}>
                      {pct(summary?.stale_count)}
                    </Typography>
                    <Typography variant="caption" color="text.secondary">
                      {summary?.stale_count != null ? `${summary.stale_count.toLocaleString()} records` : ''}
                    </Typography>
                  </Box>
                  <AlertTriangle size={22} color="#EF4444" />
                </Box>
              </CardContent>
            </CardActionArea>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card sx={{ borderLeft: '4px solid #F59E0B' }}>
            <CardActionArea onClick={() => setSectionIndex(4)}>
              <CardContent sx={{ p: 2 }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <Box>
                    <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 600 }}>
                      UNKNOWN %
                    </Typography>
                    <Typography variant="h5" sx={{ fontWeight: 700, mt: 0.5 }}>
                      {pct(summary?.unknown_count)}
                    </Typography>
                    <Typography variant="caption" color="text.secondary">
                      {summary?.unknown_count != null ? `${summary.unknown_count.toLocaleString()} records` : ''}
                    </Typography>
                  </Box>
                  <HelpCircle size={22} color="#F59E0B" />
                </Box>
              </CardContent>
            </CardActionArea>
          </Card>
        </Grid>
      </Grid>
      {!canSeeQuantity && (
        <Alert severity="info" sx={{ mb: 2 }}>
          Exact quantities are masked for your role — inventory operators holding
          inventory.update see live counts.
        </Alert>
      )}

      {/* Eight sections; switching resets pagination and the search box. */}
      <Tabs
        value={sectionIndex}
        onChange={(_, val) => {
          setSectionIndex(val);
          setPaginationModel({ page: 0, pageSize: paginationModel.pageSize });
          setSearch('');
        }}
        variant="scrollable"
        scrollButtons="auto"
        sx={{ mb: 2 }}
      >
        {SECTIONS.map((s) => (
          <Tab key={s.id} label={s.label} />
        ))}
      </Tabs>

      <AdminDataGrid
        rows={rows as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        searchPlaceholder="Search products or shops..."
        searchValue={search}
        onSearchChange={setSearch}
        onRefresh={() => refetch()}
        error={isError || !!data?.unavailable}
        errorMessage={
          data?.unavailable
            ? 'The inventory list route is not published on this deployment. These sections need the control-center backend.'
            : 'The inventory list could not be loaded. Retry, and escalate if it keeps failing.'
        }
        onRowClick={(params) => {
          const row = params.row as unknown as InventoryRow;
          if (row.shop_product_id != null) {
            router.push(ROUTES.INVENTORY_DETAIL(row.shop_product_id));
          }
        }}
      />

      <Typography variant="caption" color="text.secondary" sx={{ mt: 1.5, display: 'block' }}>
        Click a stale record to trace shop → product → last update → source in its full inventory
        record.
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