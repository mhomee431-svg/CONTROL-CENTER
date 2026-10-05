'use client';

import React, { useState, useEffect } from 'react';
import { useSearchParams, useRouter } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, Alert, Tabs, Tab } from '@mui/material';
import { Store } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AdminUserItem, ShopItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { ROUTES } from '@/core/routes/routes';
import { describeRecency } from '@/core/privacy/masking';
import { resolvePreset, spanDays } from '@/core/filters/dateRange';

/** Day window for the "New" filter, derived from the shared 30-day preset. */
const NEW_SHOPKEEPER_DAYS = spanDays(
  resolvePreset('30d').start,
  resolvePreset('30d').end
);

/** Spec quick-filters for the shopkeeper registry. */
const QUICK_FILTERS = [
  { value: 'ALL', label: 'All' },
  { value: 'NEW', label: 'New', params: { registered_within_days: NEW_SHOPKEEPER_DAYS } },
  { value: 'ACTIVE', label: 'Active', params: { status: 'ACTIVE' } },
  { value: 'SUSPENDED', label: 'Suspended', params: { status: 'SUSPENDED' } },
  { value: 'INACTIVE', label: 'Inactive', params: { status: 'INACTIVE' } },
  { value: 'INCOMPLETE', label: 'Incomplete', params: { verification_status: 'UNVERIFIED' } },
] as const;

type QuickFilter = (typeof QUICK_FILTERS)[number]['value'];

function ShopkeepersContent() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const highlightId = searchParams.get('highlight');
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [search, setSearch] = useState('');
  const [quickFilter, setQuickFilter] = useState<QuickFilter>('ALL');

  const quick = QUICK_FILTERS.find((q) => q.value === quickFilter);
  const quickParams = (quick && 'params' in quick ? quick.params : {}) as Record<string, string | number>;

  // Highlight a specific shopkeeper when drilling down from a shop or inventory record
  useEffect(() => {
    if (highlightId) setSearch('');
  }, [highlightId]);

  // Uses the dedicated shopkeepers registry endpoint. Falls back to the
  // role-filtered customers endpoint so the page still works if the dedicated
  // route is not deployed yet.
  const { data, isLoading, isError, refetch } = useQuery<{ items: AdminUserItem[]; total: number }>({
    queryKey: [
      'admin',
      'shopkeepers',
      { page: paginationModel.page, pageSize: paginationModel.pageSize, search, quickFilter },
    ],
    queryFn: async () => {
      const params = {
        ...quickParams,
        search: search || undefined,
        limit: paginationModel.pageSize,
        offset: paginationModel.page * paginationModel.pageSize,
      };
      try {
        return await apiClient<{ items: AdminUserItem[]; total: number }>(
          API_ENDPOINTS.SHOPKEEPERS.LIST,
          { params }
        );
      } catch {
        return apiClient<{ items: AdminUserItem[]; total: number }>(API_ENDPOINTS.CUSTOMERS.LIST, {
          params: { ...params, role: 'shopkeeper' },
        });
      }
    },
  });

  // Shop-derived aggregates (category / verification / product + inventory
  // counts) require the shops registry, keyed by owner.
  const { data: shopData } = useQuery<{ items: ShopItem[] }>({
    queryKey: ['admin', 'shopkeepers', 'shop-aggregates'],
    queryFn: () =>
      apiClient<{ items: ShopItem[] }>(API_ENDPOINTS.SHOPS.LIST, { params: { limit: 500 } }),
    staleTime: 60 * 1000,
  });

  const byOwner = React.useMemo(() => {
    const map = new Map<number, ShopItem[]>();
    (shopData?.items || []).forEach((s) => {
      const list = map.get(s.owner_id) || [];
      list.push(s);
      map.set(s.owner_id, list);
    });
    return map;
  }, [shopData]);

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80, cellClassName: (params) => (String(params.value) === highlightId ? 'highlighted-row' : '') },
    {
      field: 'name',
      headerName: 'Shopkeeper Name',
      flex: 1.3,
      minWidth: 170,
      renderCell: (params) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <Store size={16} color="#0F52BA" />
          <Typography variant="body2" sx={{ fontWeight: 600 }}>
            {params.value || 'Registered Shopkeeper'}
          </Typography>
        </Box>
      ),
    },
    {
      field: 'shop_category',
      headerName: 'Shop Category',
      flex: 1,
      minWidth: 140,
      // Derived from the shops this owner controls.
      valueGetter: (_v, row) => {
        const shops = byOwner.get(Number(row.id)) || [];
        return shops.length > 0 ? shops.map((s) => s.category).filter(Boolean).join(', ') : '—';
      },
    },
    {
      field: 'status',
      headerName: 'Status',
      width: 130,
      renderCell: (params) => <StatusBadge status={params.value as string} />,
    },
    {
      field: 'verification_status',
      headerName: 'Verification',
      width: 150,
      valueGetter: (_v, row) => {
        const shops = byOwner.get(Number(row.id)) || [];
        if (shops.length === 0) return 'NO SHOP';
        const allVerified = shops.every((s) => s.verification_status === 'VERIFIED');
        return allVerified ? 'VERIFIED' : shops.some((s) => s.verification_status === 'REJECTED')
          ? 'REJECTED'
          : 'PENDING';
      },
      renderCell: (params) => <StatusBadge status={params.value as string} />,
    },
    {
      field: 'product_count',
      headerName: 'Products',
      width: 110,
      align: 'right',
      headerAlign: 'right',
      valueGetter: (_v, row) => {
        const shops = byOwner.get(Number(row.id)) || [];
        return shops.reduce((s, x) => s + (x.product_count || 0), 0).toLocaleString();
      },
    },
    {
      field: 'inventory_count',
      headerName: 'Inventory',
      width: 110,
      align: 'right',
      headerAlign: 'right',
      valueGetter: (_v, row) => {
        const shops = byOwner.get(Number(row.id)) || [];
        return shops.reduce((s, x) => s + (x.inventory_count || 0), 0).toLocaleString();
      },
    },
    {
      field: 'last_activity',
      headerName: 'Last Activity',
      width: 140,
      valueGetter: (_v, row) => (row.last_login as string) || (row.created_at as string) || null,
      valueFormatter: (v) => (v ? describeRecency(v as string) : 'Never'),
    },
    {
      field: 'created_at',
      headerName: 'Created',
      width: 140,
      valueFormatter: (v) => (v ? describeRecency(v as string) : 'N/A'),
    },
  ];

  return (
    <Box>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Shopkeeper Account Registry
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Section 23 & 24: Merchant owners and retail store operators.
        </Typography>
      </Box>

      <Tabs
        value={quickFilter}
        onChange={(_, v) => {
          setQuickFilter(v);
          setPaginationModel((p) => ({ ...p, page: 0 }));
        }}
        sx={{ mb: 2, borderBottom: '1px solid #E2E8F0' }}
        variant="scrollable"
      >
        {QUICK_FILTERS.map((q) => (
          <Tab key={q.value} value={q.value} label={q.label} sx={{ textTransform: 'none' }} />
        ))}
      </Tabs>

      {isError && (
        <Alert severity="error" sx={{ mb: 2 }}>
          Could not load the shopkeeper registry.
        </Alert>
      )}

      <AdminDataGrid
        rows={(data?.items || []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        searchPlaceholder="Search shopkeeper by name or phone..."
        searchValue={search}
        onSearchChange={setSearch}
        onRefresh={() => refetch()}
        onRowClick={(p) => router.push(ROUTES.SHOPKEEPER_DETAIL(String(p.id)))}
      />
    </Box>
  );
}

export default function ShopkeepersPage() {
  return (
    <React.Suspense fallback={null}>
      <ShopkeepersContent />
    </React.Suspense>
  );
}
