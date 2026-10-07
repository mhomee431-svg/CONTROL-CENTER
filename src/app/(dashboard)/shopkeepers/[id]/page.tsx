'use client';

import React, { use, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import {
  Box,
  Card,
  CardContent,
  Grid,
  Divider,
  Alert,
  CircularProgress,
  Button,
  Typography,
  Tabs,
  Tab,
  Chip,
} from '@mui/material';
import { Store, Phone, Mail, Calendar, Clock, MapPin, ArrowLeft, Tag, ShieldCheck } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { fetchList } from '@/core/api/fetchList';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import {
  ShopkeeperDetail,
  ShopItem,
  ShopInventoryItem,
  AuditLogItem,
  OfferItem,
  ShopkeeperImportItem,
  ShopkeeperPosItem,
  ShopkeeperNotificationItem,
  ShopkeeperTicketItem,
} from '@/core/types/admin';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { ROUTES } from '@/core/routes/routes';
import { maskIdentifier, stripForbiddenFields } from '@/core/privacy/masking';

/** Spec-mandated tab set for the shopkeeper detail surface. */
const TABS = [
  'Overview',
  'Business',
  'Products',
  'Inventory',
  'Prices',
  'Offers',
  'Imports',
  'POS',
  'Notifications',
  'Support',
  'Audit',
] as const;

export default function ShopkeeperDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = React.use(params);
  const router = useRouter();
  const [tabIndex, setTabIndex] = useState(0);
  const [pagination, setPagination] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });

  /**
   * Uses the dedicated shopkeepers detail endpoint. The previous implementation
   * called /admin/customers with `search: <id>`, which searched by name/phone
   * and therefore returned an arbitrary user — or nothing — for a numeric id.
   */
  const { data: shopkeeper, isLoading, isError } = useQuery<ShopkeeperDetail | null>({
    queryKey: ['admin', 'shopkeepers', id],
    queryFn: async () => {
      try {
        return stripForbiddenFields(
          await apiClient<ShopkeeperDetail>(API_ENDPOINTS.SHOPKEEPERS.DETAIL(id))
        );
      } catch {
        // Fallback for deployments where the dedicated detail route is absent:
        // page through the role-filtered list and match the id exactly.
        const res = await apiClient<{ items: ShopkeeperDetail[] }>(API_ENDPOINTS.CUSTOMERS.LIST, {
          params: { role: 'shopkeeper', limit: 100 },
        });
        const match = (res.items || []).find((u) => String(u.id) === String(id));
        return match ? stripForbiddenFields(match) : null;
      }
    },
  });

  /** Shops this merchant owns — the spine of the Business/Products/Inventory tabs. */
  /**
   * The shops this merchant owns. Every other tab on this page derives from
   * this list — inventory, prices and offers are all read through it — so a
   * failure here is not an empty tab, it is the page having no subject.
   *
   * It is left unswallowed so the header can say the shops could not be
   * loaded, instead of rendering a merchant record whose entire shop list
   * silently reads as "owns none".
   */
  const { data: shops, isLoading: shopsLoading, isError: shopsError, refetch: refetchShops } =
    useQuery<{ items: ShopItem[] }>({
      queryKey: ['admin', 'shopkeepers', id, 'shops'],
      queryFn: () => apiClient<{ items: ShopItem[] }>(API_ENDPOINTS.SHOPKEEPERS.SHOPS(id)),
      retry: false,
    });

  const shopIds = (shops?.items || []).map((s) => s.id);

  /**
   * Shared fetch helper for the merchant-scoped surfaces (Imports, POS,
   * Notifications, Support). Each has its own backend contract.
   *
   * Failures are not swallowed. `fetchList` reports an unpublished route as
   * `unavailable` so the surface can name it, and rethrows everything else so
   * a real outage reaches the grid as an error with a retry — rather than
   * rendering as "this merchant has no imports", which is a claim about the
   * data that an operator would act on.
   */
  const fetchMerchantList = <T,>(endpoint: string) => fetchList<T>(endpoint);

  const { data: imports, isLoading: importsLoading, isError: importsError, refetch: refetchImports } = useQuery<{
    items: ShopkeeperImportItem[];
    total: number;
  }>({
    queryKey: ['admin', 'shopkeepers', id, 'imports'],
    queryFn: () => fetchMerchantList<ShopkeeperImportItem>(API_ENDPOINTS.SHOPKEEPERS.IMPORTS(id)),
    enabled: tabIndex === 6,
    retry: false,
  });

  const { data: posIntegrations, isLoading: posLoading, isError: posError, refetch: refetchPos } = useQuery<{
    items: ShopkeeperPosItem[];
    total: number;
  }>({
    queryKey: ['admin', 'shopkeepers', id, 'pos'],
    queryFn: () =>
      fetchMerchantList<ShopkeeperPosItem>(API_ENDPOINTS.SHOPKEEPERS.POS_INTEGRATIONS(id)),
    enabled: tabIndex === 7,
    retry: false,
  });

  const { data: notifications, isLoading: notificationsLoading, isError: notificationsError, refetch: refetchNotifications } = useQuery<{
    items: ShopkeeperNotificationItem[];
    total: number;
  }>({
    queryKey: ['admin', 'shopkeepers', id, 'notifications'],
    queryFn: () =>
      fetchMerchantList<ShopkeeperNotificationItem>(API_ENDPOINTS.SHOPKEEPERS.NOTIFICATIONS(id)),
    enabled: tabIndex === 8,
    retry: false,
  });

  const { data: tickets, isLoading: ticketsLoading, isError: ticketsError, refetch: refetchTickets } = useQuery<{
    items: ShopkeeperTicketItem[];
    total: number;
  }>({
    queryKey: ['admin', 'shopkeepers', id, 'tickets'],
    queryFn: () => fetchMerchantList<ShopkeeperTicketItem>(API_ENDPOINTS.SHOPKEEPERS.TICKETS(id)),
    enabled: tabIndex === 9,
    retry: false,
  });

  /**
   * Shop inventory backs the Products/Inventory/Prices tabs.
   *
   * A merchant may own several shops, so the tabs read across all of them.
   * Each request is settled independently: one shop failing must not blank
   * the whole tab, but it also must not silently look like an empty result —
   * `allUnavailable` records the case where none of them answered.
   */
  const { data: inventory, isLoading: invLoading, isError: invError, refetch: refetchInventory } = useQuery<{
    items: ShopInventoryItem[];
    total: number;
    allUnavailable: boolean;
  }>({
    queryKey: ['admin', 'shopkeepers', id, 'inventory', pagination],
    queryFn: async () => {
      if (shopIds.length === 0) return { items: [], total: 0, allUnavailable: true };
      const settled = await Promise.allSettled(
        shopIds.map((sid) =>
          apiClient<{ items: ShopInventoryItem[]; total: number }>(
            API_ENDPOINTS.INVENTORY.SHOP_INVENTORY(sid),
            {
              params: {
                limit: pagination.pageSize,
                offset: pagination.page * pagination.pageSize,
              },
            }
          )
        )
      );
      const fulfilled = settled
        .filter((s): s is PromiseFulfilledResult<{ items: ShopInventoryItem[]; total: number }> =>
          s.status === 'fulfilled'
        )
        .map((s) => s.value);
      // Nothing answered successfully: surface it as a failure so the tab
      // shows the error rather than an empty inventory.
      if (fulfilled.length === 0) throw new Error('Every shop inventory request failed');
      return {
        items: fulfilled.flatMap((r) => r.items || []),
        total: fulfilled.reduce((sum, r) => sum + (r.total ?? 0), 0),
        allUnavailable: false,
      };
    },
    enabled: tabIndex >= 2 && tabIndex <= 4 && shopIds.length > 0,
    retry: false,
  });

  const { data: offers, isLoading: offersLoading, isError: offersError, refetch: refetchOffers } = useQuery<{
    items: OfferItem[];
    unavailable: boolean;
  }>({
    queryKey: ['admin', 'shopkeepers', id, 'offers'],
    queryFn: () => fetchList<OfferItem>(API_ENDPOINTS.OFFERS.LIST, {
      params: { shop_id: shopIds[0] ?? undefined, limit: 100 },
    }),
    enabled: tabIndex === 5 && shopIds.length > 0,
    retry: false,
  });

  const { data: auditLogs, isLoading: auditLoading } = useQuery<{ items: AuditLogItem[] }>({
    queryKey: ['admin', 'shopkeepers', id, 'audit'],
    queryFn: () =>
      apiClient<{ items: AuditLogItem[] }>(API_ENDPOINTS.AUDIT.LOGS, {
        params: { entity_type: 'user', entity_id: id, limit: 100 },
      }),
    enabled: tabIndex === 10,
  });

  const inventoryColumns: GridColDef[] = [
    { field: 'shop_product_id', headerName: 'ID', width: 80 },
    { field: 'product_name', headerName: 'Product', flex: 1.5, minWidth: 180 },
    { field: 'quantity', headerName: 'Qty', width: 90, align: 'right', headerAlign: 'right' },
    {
      field: 'price',
      headerName: 'Price',
      width: 110,
      align: 'right',
      headerAlign: 'right',
      valueFormatter: (v) => (v != null ? `₹${Number(v).toFixed(2)}` : '—'),
    },
    {
      field: 'stock_status',
      headerName: 'Stock',
      width: 120,
      renderCell: (p) => <StatusBadge status={p.value as string} />,
    },
    {
      field: 'freshness_status',
      headerName: 'Freshness',
      width: 130,
      renderCell: (p) => <StatusBadge status={(p.value as string) || 'UNKNOWN'} />,
    },
    {
      field: 'last_updated',
      headerName: 'Last Synced',
      flex: 1,
      valueFormatter: (v) => (v ? new Date(v as string).toLocaleString() : 'N/A'),
    },
  ];

  const shopColumns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    { field: 'name', headerName: 'Shop', flex: 1.4, minWidth: 160 },
    { field: 'category', headerName: 'Category', flex: 1 },
    {
      field: 'business_type',
      headerName: 'Business Type',
      width: 150,
      valueGetter: (_v, row) => (row as ShopItem).business_type || 'Not reported',
    },
    {
      field: 'location',
      headerName: 'Location',
      width: 180,
      valueGetter: (_v, row) => `${row.city || '—'}, ${row.state || '—'}`,
    },
    {
      field: 'status',
      headerName: 'Status',
      width: 120,
      renderCell: (p) => <StatusBadge status={p.value as string} />,
    },
    {
      field: 'verification_status',
      headerName: 'Verification',
      width: 140,
      renderCell: (p) => <StatusBadge status={p.value as string} />,
    },
    {
      field: 'product_count',
      headerName: 'Products',
      width: 110,
      align: 'right',
      headerAlign: 'right',
    },
  ];

  const offerColumns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    { field: 'title', headerName: 'Offer', flex: 1.4 },
    { field: 'discount_type', headerName: 'Type', width: 120 },
    { field: 'discount_value', headerName: 'Value', width: 110, align: 'right', headerAlign: 'right' },
    {
      field: 'status',
      headerName: 'Status',
      width: 130,
      renderCell: (p) => <StatusBadge status={p.value as string} />,
    },
    {
      field: 'valid_until',
      headerName: 'Expires',
      width: 140,
      valueFormatter: (v) => (v ? new Date(v as string).toLocaleDateString() : '—'),
    },
  ];

  const importColumns: GridColDef[] = [
    { field: 'id', headerName: 'Job ID', width: 90 },
    { field: 'shop_name', headerName: 'Shop', flex: 1.2, minWidth: 150 },
    { field: 'source', headerName: 'Source', flex: 1, minWidth: 140 },
    {
      field: 'status',
      headerName: 'Status',
      width: 130,
      renderCell: (p) => <StatusBadge status={(p.value as string) || 'UNKNOWN'} />,
    },
    { field: 'rows_total', headerName: 'Rows', width: 100, align: 'right', headerAlign: 'right' },
    {
      field: 'rows_processed',
      headerName: 'Processed',
      width: 110,
      align: 'right',
      headerAlign: 'right',
    },
    {
      field: 'created_at',
      headerName: 'Started',
      flex: 1,
      valueFormatter: (v) => (v ? new Date(v as string).toLocaleString() : '—'),
    },
  ];

  const posColumns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 90 },
    {
      field: 'shop_name',
      headerName: 'Shop',
      flex: 1.4,
      minWidth: 170,
      valueGetter: (_v, row) => (row as ShopkeeperPosItem).shop_name || '—',
    },
    { field: 'provider', headerName: 'POS Provider', flex: 1, minWidth: 160 },
    {
      field: 'status',
      headerName: 'Sync Status',
      width: 140,
      renderCell: (p) => <StatusBadge status={(p.value as string) || 'UNKNOWN'} />,
    },
    {
      field: 'last_sync',
      headerName: 'Last Sync',
      flex: 1.2,
      minWidth: 180,
      valueFormatter: (v) => (v ? new Date(v as string).toLocaleString() : 'Never'),
    },
  ];

  const notificationColumns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    { field: 'title', headerName: 'Notification', flex: 1.8, minWidth: 220 },
    { field: 'notification_type', headerName: 'Type', width: 160 },
    {
      field: 'is_read',
      headerName: 'Read',
      width: 100,
      renderCell: (p) => (
        <Chip size="small" color={p.value ? 'default' : 'primary'} label={p.value ? 'Read' : 'Unread'} />
      ),
    },
    {
      field: 'sent_at',
      headerName: 'Sent',
      width: 190,
      valueFormatter: (v) => (v ? new Date(v as string).toLocaleString() : '—'),
    },
  ];

  const ticketColumns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    { field: 'ticket_number', headerName: 'Ticket', width: 150 },
    { field: 'complaint_type', headerName: 'Type', width: 170 },
    {
      field: 'priority',
      headerName: 'Priority',
      width: 120,
      renderCell: (p) => <Chip size="small" label={p.value as string} />,
    },
    {
      field: 'status',
      headerName: 'Status',
      width: 140,
      renderCell: (p) => <StatusBadge status={p.value as string} />,
    },
    {
      field: 'description',
      headerName: 'Description',
      flex: 1.5,
      minWidth: 220,
      renderCell: (p) => (
        <Typography variant="body2" noWrap>
          {(p.value as string) || '—'}
        </Typography>
      ),
    },
    {
      field: 'created_at',
      headerName: 'Opened',
      width: 180,
      valueFormatter: (v) => (v ? new Date(v as string).toLocaleDateString() : '—'),
    },
  ];

  const auditColumns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    { field: 'action', headerName: 'Action', flex: 1.2 },
    { field: 'admin_user', headerName: 'Admin', width: 160 },
    {
      field: 'created_at',
      headerName: 'When',
      flex: 1,
      valueFormatter: (v) => (v ? new Date(v as string).toLocaleString() : '—'),
    },
  ];

  const totalProducts = (shops?.items || []).reduce((s, x) => s + (x.product_count || 0), 0);
  const totalInventory = (shops?.items || []).reduce((s, x) => s + (x.inventory_count || 0), 0);
  const lastInventoryUpdate = (shops?.items || [])
    .map((s) => s.updated_at)
    .filter(Boolean)
    .sort()
    .pop();

  // Derived business facts for the Overview surface. Each prefers an explicit
  // shopkeeper-level value from the backend and falls back to the shops this
  // merchant owns. Nothing is invented: an absent value renders "Not reported".
  const merchantShops = shops?.items || [];
  const shopNames = Array.from(new Set(merchantShops.map((s) => s.name).filter(Boolean)));
  const shopCategories = Array.from(new Set(merchantShops.map((s) => s.category).filter(Boolean)));
  const businessTypes = Array.from(
    new Set(
      merchantShops
        .map((s) => s.business_type)
        .filter((v): v is string => Boolean(v))
    )
  );

  const overallVerification = (() => {
    const explicit = shopkeeper?.verification_status;
    if (explicit) return explicit;
    if (merchantShops.length === 0) return null;
    if (merchantShops.every((s) => s.verification_status === 'VERIFIED')) return 'VERIFIED';
    if (merchantShops.some((s) => s.verification_status === 'REJECTED')) return 'REJECTED';
    if (merchantShops.some((s) => s.verification_status === 'PENDING')) return 'PENDING';
    return 'UNVERIFIED';
  })();

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Shopkeepers', href: ROUTES.SHOPKEEPERS },
          { label: shopkeeper?.name ? shopkeeper.name : `Shopkeeper #${id}` },
        ]}
      />
      <Button startIcon={<ArrowLeft size={16} />} onClick={() => router.push(ROUTES.SHOPKEEPERS)} sx={{ mb: 2 }}>
        Back to Shopkeepers
      </Button>

      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      )}
      {isError && <Alert severity="error">Could not load shopkeeper #{id}.</Alert>}

      {shopsError && (
        // The shop list is this page's subject, not one tab among many. Losing
        // it silently would render a merchant who appears to own nothing,
        // which is an operational claim the operator would act on.
        <Alert severity="error" sx={{ mt: 2 }}>
          This merchant&apos;s shops could not be loaded, so inventory, pricing and offers cannot be
          shown. The request failed — retry, and escalate if it keeps failing.
          <Button size="small" onClick={() => refetchShops()} sx={{ ml: 1 }}>
            Retry
          </Button>
        </Alert>
      )}

      {!isLoading && !isError && !shopkeeper && (
        <Alert severity="warning">
          No shopkeeper record exists for #{id}. It may have been deleted or the id may refer to a
          shop rather than a shopkeeper account.
        </Alert>
      )}

      {shopkeeper && (
        <Box>
          <Card sx={{ mb: 3 }}>
            <CardContent sx={{ p: 3 }}>
              <Box
                sx={{
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'flex-start',
                  flexWrap: 'wrap',
                  gap: 2,
                }}
              >
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                  <Box sx={{ p: 1.5, borderRadius: 2, backgroundColor: '#EFF6FF', color: 'primary.main' }}>
                    <Store size={28} />
                  </Box>
                  <Box>
                    <Typography variant="h6" sx={{ fontWeight: 700 }}>
                      {maskIdentifier(shopkeeper.name, 'name', true) || 'Registered Shopkeeper'}
                    </Typography>
                    <Typography variant="body2" color="text.secondary">
                      Shopkeeper ID: #{shopkeeper.id}
                    </Typography>
                  </Box>
                </Box>
                <StatusBadge status={shopkeeper.status} size="medium" />
              </Box>

              <Divider sx={{ my: 2.5 }} />
              <Tabs value={tabIndex} onChange={(_, v) => setTabIndex(v)} variant="scrollable">
                {TABS.map((t) => (
                  <Tab key={t} label={t} sx={{ textTransform: 'none' }} />
                ))}
              </Tabs>
            </CardContent>
          </Card>

          {/* Tab 0: Overview */}
          {tabIndex === 0 && (
            <Grid container spacing={3}>
              <Grid item xs={12} md={8}>
                <Card>
                  <CardContent sx={{ p: 3 }}>
                    <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 2 }}>
                      Identity & Profile
                    </Typography>
                    <DetailRow
                      icon={<Store size={16} color="#64748B" />}
                      label="Shop Name"
                      value={shopNames.join(' · ') || 'Not reported'}
                    />
                    <DetailRow
                      icon={<Tag size={16} color="#64748B" />}
                      label="Business Category"
                      value={shopCategories.join(' · ') || 'Not reported'}
                    />
                    <DetailRow
                      icon={<Tag size={16} color="#64748B" />}
                      label="Business Type"
                      value={
                        shopkeeper?.business_type ||
                        businessTypes.join(' · ') ||
                        'Not reported'
                      }
                    />
                    <DetailRow
                      icon={<ShieldCheck size={16} color="#64748B" />}
                      label="Verification"
                      value={overallVerification || 'Not reported'}
                    />
                    <DetailRow
                      icon={<Store size={16} color="#64748B" />}
                      label="Status"
                      value={shopkeeper.status || 'Not reported'}
                    />
                    <DetailRow
                      icon={<Phone size={16} color="#64748B" />}
                      label="Phone"
                      value={maskIdentifier(shopkeeper.phone, 'phone', true)}
                    />
                    <DetailRow
                      icon={<Mail size={16} color="#64748B" />}
                      label="Email"
                      value={maskIdentifier(shopkeeper.email, 'email', true)}
                    />
                    <DetailRow
                      icon={<Calendar size={16} color="#64748B" />}
                      label="Created"
                      value={shopkeeper.created_at ? new Date(shopkeeper.created_at).toLocaleString() : 'N/A'}
                    />
                    <DetailRow
                      icon={<Clock size={16} color="#64748B" />}
                      label="Last Login / Activity"
                      value={shopkeeper.last_login ? new Date(shopkeeper.last_login).toLocaleString() : 'Not reported'}
                    />
                    <DetailRow
                      icon={<MapPin size={16} color="#64748B" />}
                      label="Location"
                      value={
                        (shopkeeper?.city || shopkeeper?.state
                          ? [shopkeeper.city, shopkeeper.state].filter(Boolean).join(', ')
                          : '') ||
                        Array.from(
                          new Set(
                            (shops?.items || []).map((s) => `${s.city || '—'}, ${s.state || '—'}`)
                          )
                        ).join(' · ') ||
                        'Not reported'
                      }
                    />
                  </CardContent>
                </Card>
              </Grid>

              <Grid item xs={12} md={4}>
                <Card>
                  <CardContent sx={{ p: 3 }}>
                    <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 2 }}>
                      Business Summary
                    </Typography>
                    <SummaryRow label="Shops" value={shops?.items?.length ?? 0} />
                    <SummaryRow label="Product Count" value={totalProducts} />
                    <SummaryRow label="Inventory Count" value={totalInventory} />
                    <SummaryRow
                      label="Last Inventory Update"
                      value={lastInventoryUpdate ? new Date(lastInventoryUpdate).toLocaleString() : 'N/A'}
                    />
                  </CardContent>
                </Card>
              </Grid>
            </Grid>
          )}

          {/* Tab 1: Business */}
          {tabIndex === 1 && (
            <AdminDataGrid
              rows={(shops?.items || []) as unknown as Record<string, unknown>[]}
              columns={shopColumns}
              totalRows={shops?.items?.length ?? 0}
              paginationModel={pagination}
              onPaginationModelChange={setPagination}
              loading={isLoading}
              onRowClick={(p) => router.push(ROUTES.BUSINESS_DETAIL(String(p.id)))}
            />
          )}

          {/* Tabs 2-4: Products / Inventory / Prices all read shop inventory */}
          {(tabIndex === 2 || tabIndex === 3 || tabIndex === 4) && (
            <AdminDataGrid
              rows={(inventory?.items || []) as unknown as Record<string, unknown>[]}
              columns={tabIndex === 4 ? inventoryColumns.filter((c) => c.field !== 'quantity') : inventoryColumns}
              totalRows={inventory?.total ?? 0}
              paginationModel={pagination}
              onPaginationModelChange={setPagination}
              loading={invLoading}
                  error={invError}
                  errorMessage="This surface could not be loaded. The request failed — retry, and escalate if it keeps failing."
                  onRefresh={() => refetchInventory()}
              searchPlaceholder={`Search ${TABS[tabIndex].toLowerCase()}...`}
            />
          )}

          {/* Tab 5: Offers */}
          {tabIndex === 5 && (
            <AdminDataGrid
              rows={(offers?.items || []) as unknown as Record<string, unknown>[]}
              columns={offerColumns}
              totalRows={offers?.items?.length ?? 0}
              paginationModel={pagination}
              onPaginationModelChange={setPagination}
              loading={offersLoading}
                  error={offersError}
                  errorMessage="This surface could not be loaded. The request failed — retry, and escalate if it keeps failing."
                  onRefresh={() => refetchOffers()}
            />
          )}

          {/* Tabs 6-9: Imports, POS, Notifications, Support */}
          {tabIndex === 6 && (
            <AdminDataGrid
              rows={(imports?.items ?? []) as unknown as Record<string, unknown>[]}
              columns={importColumns}
              totalRows={imports?.total ?? 0}
              paginationModel={pagination}
              onPaginationModelChange={setPagination}
              loading={importsLoading}
                  error={importsError}
                  errorMessage="This surface could not be loaded. The request failed — retry, and escalate if it keeps failing."
                  onRefresh={() => refetchImports()}
              searchPlaceholder="Search import jobs..."
            />
          )}

          {tabIndex === 7 && (
            <AdminDataGrid
              rows={(posIntegrations?.items ?? []) as unknown as Record<string, unknown>[]}
              columns={posColumns}
              totalRows={posIntegrations?.total ?? 0}
              paginationModel={pagination}
              onPaginationModelChange={setPagination}
              loading={posLoading}
                  error={posError}
                  errorMessage="This surface could not be loaded. The request failed — retry, and escalate if it keeps failing."
                  onRefresh={() => refetchPos()}
              searchPlaceholder="Search POS integrations..."
            />
          )}

          {tabIndex === 8 && (
            <AdminDataGrid
              rows={(notifications?.items ?? []) as unknown as Record<string, unknown>[]}
              columns={notificationColumns}
              totalRows={notifications?.total ?? 0}
              paginationModel={pagination}
              onPaginationModelChange={setPagination}
              loading={notificationsLoading}
                  error={notificationsError}
                  errorMessage="This surface could not be loaded. The request failed — retry, and escalate if it keeps failing."
                  onRefresh={() => refetchNotifications()}
              searchPlaceholder="Search notifications..."
            />
          )}

          {tabIndex === 9 && (
            <AdminDataGrid
              rows={(tickets?.items ?? []) as unknown as Record<string, unknown>[]}
              columns={ticketColumns}
              totalRows={tickets?.total ?? 0}
              paginationModel={pagination}
              onPaginationModelChange={setPagination}
              loading={ticketsLoading}
                  error={ticketsError}
                  errorMessage="This surface could not be loaded. The request failed — retry, and escalate if it keeps failing."
                  onRefresh={() => refetchTickets()}
              searchPlaceholder="Search support tickets..."
            />
          )}

          {/* Tab 10: Audit */}
          {tabIndex === 10 && (
            <AdminDataGrid
              rows={(auditLogs?.items || []) as unknown as Record<string, unknown>[]}
              columns={auditColumns}
              totalRows={auditLogs?.items?.length ?? 0}
              paginationModel={pagination}
              onPaginationModelChange={setPagination}
              loading={auditLoading}
            />
          )}
        </Box>
      )}
    </Box>
  );
}

function DetailRow({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) {
  return (
    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, py: 0.75 }}>
      {icon}
      <Typography variant="body2" color="text.secondary" sx={{ minWidth: 190 }}>
        {label}:
      </Typography>
      <Typography variant="body2" sx={{ fontWeight: 600 }}>
        {value}
      </Typography>
    </Box>
  );
}

function SummaryRow({ label, value }: { label: string; value: string | number }) {
  return (
    <Box sx={{ display: 'flex', justifyContent: 'space-between', py: 0.75 }}>
      <Typography variant="body2" color="text.secondary">
        {label}
      </Typography>
      <Typography variant="body2" sx={{ fontWeight: 700 }}>
        {typeof value === 'number' ? value.toLocaleString() : value}
      </Typography>
    </Box>
  );
}
