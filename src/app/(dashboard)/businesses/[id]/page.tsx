'use client';

import React, { use, useState, useMemo } from 'react';
import { useRouter } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import {
  Box,
  Typography,
  Card,
  CardContent,
  Grid,
  Button,
  Tabs,
  Tab,
  Divider,
  Alert,
  Chip,
  CircularProgress,
  List,
  ListItem,
  ListItemText,
} from '@mui/material';
import { ArrowLeft, Store, MapPin } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { fetchList } from '@/core/api/fetchList';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import {
  ShopItem,
  ShopInventoryItem,
  ShopDocumentItem,
  ShopPricingItem,
  AuditLogItem,
} from '@/core/types/admin';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import {
  DetailField,
  TabSection,
  NotReported,
  ListState,
  ExternalLink,
} from '@/core/components/BusinessDetailParts';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';

/**
 * Business drill-down.
 *
 * Fourteen tabs, one operator question each. The split matters on an admin
 * console: "does this business have documents" and "is this business
 * verified" are different decisions, and burying them in one long profile
 * page is how the wrong one gets answered.
 *
 * Every tab reads from a named endpoint. Where the backend has not published a
 * route the tab says so explicitly instead of rendering an empty grid, which
 * an operator would read as missing data.
 */

const TABS = [
  'Business Information',
  'Location',
  'Category',
  'Business Type',
  'Contact',
  'Operating Hours',
  'Status',
  'Verification',
  'Documents',
  'Products',
  'Inventory',
  'Pricing',
  'Offers',
  'History',
] as const;

const TAB = {
  INFO: 0,
  LOCATION: 1,
  CATEGORY: 2,
  BUSINESS_TYPE: 3,
  CONTACT: 4,
  HOURS: 5,
  STATUS: 6,
  VERIFICATION: 7,
  DOCUMENTS: 8,
  PRODUCTS: 9,
  INVENTORY: 10,
  PRICING: 11,
  OFFERS: 12,
  HISTORY: 13,
} as const;

const WEEKDAYS = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

const isBusiness = (tabIndex: number) => tabIndex < TAB.DOCUMENTS;

const fmtDateTime = (value?: string | null) =>
  value ? new Date(value).toLocaleString() : null;

const fmtDate = (value?: string | null) => (value ? new Date(value).toLocaleDateString() : null);

/** Normalises the operating-hours payload, which arrives as a map or a string. */
function normaliseHours(value: ShopItem['operating_hours']): { day: string; hours: string | null }[] {
  if (!value) return [];
  if (typeof value === 'string') {
    return value
      .split(/[;\n]/)
      .map((line) => line.trim())
      .filter(Boolean)
      .map((line) => {
        const [day, ...rest] = line.split(/[:\-–]/);
        return { day: day.trim(), hours: rest.join('-').trim() || null };
      });
  }
  return Object.entries(value).map(([day, hours]) => ({
    day,
    hours: hours ?? null,
  }));
}

export default function BusinessDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const resolvedParams = use(params);
  const router = useRouter();
  const shopId = resolvedParams.id;
  const [tabIndex, setTabIndex] = useState(0);
  const [invPagination, setInvPagination] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [logPagination, setLogPagination] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [docPagination, setDocPagination] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [pricePagination, setPricePagination] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [invSearch, setInvSearch] = useState('');
  const [logSearch, setLogSearch] = useState('');
  const [docSearch, setDocSearch] = useState('');
  const [priceSearch, setPriceSearch] = useState('');

  const {
    data: shop,
    isLoading,
    isError: shopError,
    refetch: refetchShop,
  } = useQuery<ShopItem>({
    queryKey: ['admin', 'shops', shopId],
    queryFn: () => apiClient<ShopItem>(API_ENDPOINTS.SHOPS.DETAIL(shopId)),
  });

  /**
   * Each tab's list is enabled only while that tab is open, so opening the
   * record issues one request rather than six. `fetchList` separates an
   * unpublished route from a failed one, which is what lets each tab say
   * which of the two it is showing.
   */
  const shopList = <T,>(endpoint: string, params: Record<string, unknown>) =>
    fetchList<T>(endpoint, {
      params: Object.entries(params).reduce<Record<string, string | number>>((acc, [k, v]) => {
        if (v !== undefined && v !== null && v !== '') acc[k] = v as string | number;
        return acc;
      }, {}),
    });

  const {
    data: documents,
    isLoading: docsLoading,
    isError: docsError,
    isFetching: docsFetching,
    refetch: refetchDocuments,
  } = useQuery({
    queryKey: ['admin', 'shops', shopId, 'documents', docPagination, docSearch],
    queryFn: () =>
      shopList<ShopDocumentItem>(API_ENDPOINTS.SHOPS.DOCUMENTS(shopId), {
        search: docSearch || undefined,
        limit: docPagination.pageSize,
        offset: docPagination.page * docPagination.pageSize,
      }),
    enabled: tabIndex === TAB.DOCUMENTS,
    retry: false,
  });

  const {
    data: pricing,
    isLoading: priceLoading,
    isError: priceError,
    isFetching: priceFetching,
    refetch: refetchPricing,
  } = useQuery({
    queryKey: ['admin', 'shops', shopId, 'pricing', pricePagination, priceSearch],
    queryFn: () =>
      shopList<ShopPricingItem>(API_ENDPOINTS.SHOPS.PRICING(shopId), {
        search: priceSearch || undefined,
        limit: pricePagination.pageSize,
        offset: pricePagination.page * pricePagination.pageSize,
      }),
    enabled: tabIndex === TAB.PRICING,
    retry: false,
  });

  const {
    data: shopProducts,
    isLoading: productsLoading,
    isError: productsError,
    isFetching: productsFetching,
    refetch: refetchProducts,
  } = useQuery({
    queryKey: ['admin', 'shops', shopId, 'products', docPagination, docSearch],
    queryFn: () =>
      shopList<Record<string, unknown>>(API_ENDPOINTS.PRODUCTS.LIST, {
        shop_id: shopId,
        search: docSearch || undefined,
        limit: docPagination.pageSize,
        offset: docPagination.page * docPagination.pageSize,
      }),
    enabled: tabIndex === TAB.PRODUCTS,
    retry: false,
  });

  const {
    data: shopOffers,
    isLoading: offersLoading,
    isError: offersError,
    isFetching: offersFetching,
    refetch: refetchOffers,
  } = useQuery({
    queryKey: ['admin', 'shops', shopId, 'offers', docPagination, docSearch],
    queryFn: () =>
      shopList<Record<string, unknown>>(API_ENDPOINTS.OFFERS.LIST, {
        shop_id: shopId,
        limit: docPagination.pageSize,
        offset: docPagination.page * docPagination.pageSize,
      }),
    enabled: tabIndex === TAB.OFFERS,
    retry: false,
  });

  // Drill-down: this shop's inventory records
  const {
    data: shopInventory,
    isLoading: invLoading,
    isError: invError,
    refetch: refetchInventory,
  } = useQuery<{
    items: ShopInventoryItem[];
    total: number;
  }>({
    queryKey: ['admin', 'shops', shopId, 'inventory', invPagination, invSearch],
    queryFn: () =>
      apiClient<{ items: ShopInventoryItem[]; total: number }>(
        API_ENDPOINTS.INVENTORY.SHOP_INVENTORY(shopId),
        {
          params: {
            search: invSearch || undefined,
            limit: invPagination.pageSize,
            offset: invPagination.page * invPagination.pageSize,
          },
        }
      ),
    enabled: tabIndex === TAB.INVENTORY,
  });

  // Drill-down: this shop's audit trail
  const {
    data: auditLogs,
    isLoading: logsLoading,
    isError: logsError,
    refetch: refetchLogs,
  } = useQuery<{
    items: AuditLogItem[];
    total: number;
  }>({
    queryKey: ['admin', 'shops', shopId, 'audit-logs', logPagination, logSearch],
    queryFn: () =>
      apiClient<{ items: AuditLogItem[]; total: number }>(API_ENDPOINTS.AUDIT.LOGS, {
        params: {
          entity_type: 'shop',
          entity_id: shopId,
          search: logSearch || undefined,
          limit: logPagination.pageSize,
          offset: logPagination.page * logPagination.pageSize,
        },
      }),
    enabled: tabIndex === TAB.HISTORY,
  });

  const hours = useMemo(() => normaliseHours(shop?.operating_hours), [shop?.operating_hours]);
const docColumns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    { field: 'doc_type', headerName: 'Type', width: 160 },
    { field: 'title', headerName: 'Document', flex: 1.5, minWidth: 200 },
    { field: 'file_name', headerName: 'File', flex: 1, minWidth: 160 },
    {
      field: 'status',
      headerName: 'Status',
      width: 130,
      renderCell: (params) => <StatusBadge status={(params.value as string) || 'PENDING'} />,
    },
    {
      field: 'expires_at',
      headerName: 'Expires',
      width: 140,
      valueFormatter: (value) => fmtDate(value as string) ?? '—',
    },
    {
      field: 'file_url',
      headerName: '',
      width: 90,
      sortable: false,
      renderCell: (params) => <ExternalLink href={params.value as string}>Open</ExternalLink>,
    },
  ];

  const priceColumns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    { field: 'product_name', headerName: 'Product', flex: 1.5, minWidth: 200 },
    { field: 'barcode', headerName: 'Barcode', width: 150 },
    {
      field: 'price',
      headerName: 'Price',
      width: 110,
      align: 'right',
      valueFormatter: (value) => (value != null ? `₹${Number(value).toFixed(2)}` : '—'),
    },
    {
      field: 'mrp',
      headerName: 'MRP',
      width: 110,
      align: 'right',
      valueFormatter: (value) => (value != null ? `₹${Number(value).toFixed(2)}` : '—'),
    },
    {
      field: 'updated_at',
      headerName: 'Updated',
      flex: 1,
      valueFormatter: (value) => fmtDateTime(value as string) ?? '—',
    },
  ];

  const productColumns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    { field: 'name', headerName: 'Product', flex: 1.5, minWidth: 200 },
    { field: 'brand_name', headerName: 'Brand', width: 150 },
    { field: 'category_name', headerName: 'Category', width: 150 },
    { field: 'barcode', headerName: 'Barcode', width: 150 },
    {
      field: 'status',
      headerName: 'Status',
      width: 120,
      renderCell: (params) => <StatusBadge status={(params.value as string) || 'DRAFT'} />,
    },
  ];

  const offerColumns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    { field: 'title', headerName: 'Offer', flex: 1.5, minWidth: 200 },
    { field: 'discount_type', headerName: 'Type', width: 120 },
    { field: 'discount_value', headerName: 'Value', width: 110, align: 'right' },
    {
      field: 'status',
      headerName: 'Status',
      width: 120,
      renderCell: (params) => <StatusBadge status={(params.value as string) || 'INACTIVE'} />,
    },
    {
      field: 'starts_at',
      headerName: 'Starts',
      width: 150,
      valueFormatter: (value) => fmtDate(value as string) ?? '—',
    },
    {
      field: 'ends_at',
      headerName: 'Ends',
      width: 150,
      valueFormatter: (value) => fmtDate(value as string) ?? '—',
    },
  ];

  const invColumns: GridColDef[] = [
    { field: 'shop_product_id', headerName: 'ID', width: 80 },
    { field: 'product_name', headerName: 'Product', flex: 1.5, minWidth: 180 },
    { field: 'quantity', headerName: 'Qty', width: 90, align: 'right' },
    {
      field: 'price',
      headerName: 'Price',
      width: 110,
      align: 'right',
      valueFormatter: (value) => (value != null ? `₹${value}` : '—'),
    },
    {
      field: 'stock_status',
      headerName: 'Stock',
      width: 120,
      renderCell: (params) => <StatusBadge status={params.value as string} />,
    },
    {
      field: 'freshness_status',
      headerName: 'Freshness',
      width: 120,
      renderCell: (params) => <StatusBadge status={(params.value as string) || 'UNKNOWN'} />,
    },
    {
      field: 'last_updated',
      headerName: 'Last Synced',
      flex: 1,
      valueFormatter: (value) => (value ? new Date(value as string).toLocaleString() : 'N/A'),
    },
  ];

  const logColumns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    { field: 'action', headerName: 'Action', flex: 1 },
    { field: 'admin_user', headerName: 'Admin', width: 160 },
    {
      field: 'created_at',
      headerName: 'When',
      flex: 1,
      valueFormatter: (value) => (value ? new Date(value as string).toLocaleString() : '—'),
    },
  ];

return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: '/dashboard' },
          { label: 'Businesses', href: '/businesses' },
          { label: shop?.name ? shop.name : `Business #${shopId}` },
        ]}
      />
      <Button startIcon={<ArrowLeft size={16} />} onClick={() => router.push('/businesses')} sx={{ mb: 2 }}>
        Back to Businesses
      </Button>

      {/* Identity header — always visible, so the operator never has to leave a
          tab to confirm which business they are acting on. */}
      <Card sx={{ mb: 2 }}>
        <CardContent sx={{ p: 3 }}>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, flexWrap: 'wrap' }}>
            <Box sx={{ p: 1.2, borderRadius: 2, backgroundColor: '#EFF6FF', color: 'primary.main', display: 'flex' }}>
              <Store size={24} />
            </Box>
            <Box sx={{ flex: 1, minWidth: 200 }}>
              <Typography variant="h6" sx={{ fontWeight: 700 }}>
                {shop?.name || `Business #${shopId}`}
              </Typography>
              <Box sx={{ display: 'flex', gap: 1, alignItems: 'center', flexWrap: 'wrap', mt: 0.5 }}>
                <Typography variant="body2" color="text.secondary">
                  ID #{shopId}
                </Typography>
                {shop?.city && (
                  <Typography variant="body2" color="text.secondary">
                    · <MapPin size={12} style={{ verticalAlign: 'middle' }} />{' '}
                    {[shop.city, shop.state].filter(Boolean).join(', ')}
                  </Typography>
                )}
              </Box>
            </Box>
            {shop?.status && <StatusBadge status={shop.status} size="medium" />}
            {shop?.verification_status && <StatusBadge status={shop.verification_status} size="medium" />}
          </Box>
        </CardContent>
      </Card>

      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      )}

      {shopError && (
        <Alert
          severity="error"
          sx={{ mb: 2 }}
          action={
            <Button color="inherit" size="small" onClick={() => refetchShop()}>
              Retry
            </Button>
          }
        >
          This business record could not be loaded. The request failed — retry, and escalate if it keeps failing.
        </Alert>
      )}

      {!isLoading && !shopError && !shop && (
        <Alert severity="warning">
          No business record exists for #{shopId}. It may have been deleted, or the id may refer to
          something other than a business.
        </Alert>
      )}

      {shop && (
        <>
          <Tabs
            value={tabIndex}
            onChange={(_, val) => setTabIndex(val)}
            variant="scrollable"
            scrollButtons="auto"
            sx={{ mb: 2, borderBottom: 1, borderColor: 'divider' }}
          >
            {TABS.map((label) => (
              <Tab key={label} label={label} />
            ))}
          </Tabs>

          {/* 1 — Business Information */}
          {tabIndex === TAB.INFO && (
            <TabSection title="Business Information" description="Identity and ownership for this business record.">
              <Grid container spacing={2}>
                <Grid item xs={12} md={6}>
                  <DetailField label="Business name" value={shop.name} />
                  <DetailField label="Business ID" value={shop.id} mono />
                  <DetailField label="Owner (shopkeeper)" value={shop.owner_name} />
                  <DetailField label="Owner ID" value={shop.owner_id} mono />
                </Grid>
                <Grid item xs={12} md={6}>
                  <DetailField label="Registration number" value={shop.registration_number} mono />
                  <DetailField label="GST number" value={shop.gst_number} mono />
                  <DetailField label="Registered" value={fmtDateTime(shop.created_at)} />
                  <DetailField label="Last updated" value={fmtDateTime(shop.updated_at)} />
                </Grid>
              </Grid>
              {shop.description && (
                <Box sx={{ mt: 2 }}>
                  <DetailField label="Description" value={shop.description} />
                </Box>
              )}
            </TabSection>
          )}

          {/* 2 — Location */}
          {tabIndex === TAB.LOCATION && (
            <TabSection title="Location" description="Where this business operates.">
              <Grid container spacing={2}>
                <Grid item xs={12} md={6}>
                  <DetailField label="Address" value={shop.address} />
                  <DetailField label="Locality" value={shop.locality} />
                  <DetailField label="City" value={shop.city} />
                  <DetailField label="Pincode" value={shop.pincode} mono />
                </Grid>
                <Grid item xs={12} md={6}>
                  <DetailField label="State" value={shop.state} />
                  <DetailField
                    label="Coordinates"
                    mono
                    value={shop.latitude != null && shop.longitude != null ? `${shop.latitude}, ${shop.longitude}` : null}
                  />
                  {shop.latitude != null && shop.longitude != null && (
                    <ExternalLink href={`https://www.openstreetmap.org/?mlat=${shop.latitude}&mlon=${shop.longitude}`}>
                      View on map
                    </ExternalLink>
                  )}
                  <DetailField label="Products mapped" value={shop.product_count} />
                </Grid>
              </Grid>
              {!shop.address && !shop.locality && !shop.pincode && !shop.latitude && (
                <NotReported what="A street-level address" />
              )}
            </TabSection>
          )}

          {/* 3 — Category */}
          {tabIndex === TAB.CATEGORY && (
            <TabSection title="Category" description="The taxonomy this business is filed under.">
              <DetailField label="Category" value={shop.category} />
              <DetailField label="Category ID" value={shop.category_id} mono />
              <DetailField label="Subcategory" value={shop.subcategory} />
              {!shop.category && <NotReported what="A category" />}
            </TabSection>
          )}

          {/* 4 — Business Type */}
          {tabIndex === TAB.BUSINESS_TYPE && (
            <TabSection
              title="Business Type"
              description="The trading model, which decides which platform features apply."
            >
              <DetailField label="Business type" value={shop.business_type} />
              {shop.business_type && (
                <Chip
                  size="small"
                  label={shop.business_type}
                  sx={{ mt: 1, backgroundColor: '#EFF6FF', color: 'primary.main' }}
                />
              )}
              {!shop.business_type && <NotReported what="A business type" />}
            </TabSection>
          )}

          {/* 5 — Contact */}
          {tabIndex === TAB.CONTACT && (
            <TabSection title="Contact" description="How this business can be reached. Unreported fields are marked, not blank.">
              <Grid container spacing={2}>
                <Grid item xs={12} md={6}>
                  <DetailField label="Phone" value={shop.phone} mono />
                  <DetailField label="Alternate phone" value={shop.alt_phone} mono />
                </Grid>
                <Grid item xs={12} md={6}>
                  <DetailField label="Email" value={shop.email} mono />
                  <DetailField label="Website" value={<ExternalLink href={shop.website}>Website</ExternalLink>} />
                </Grid>
              </Grid>
              {!shop.phone && !shop.email && !shop.website && <NotReported what="Contact details" />}
            </TabSection>
          )}

          {/* 6 — Operating Hours */}
          {tabIndex === TAB.HOURS && (
            <TabSection title="Operating Hours" description="Published trading hours for this business.">
              {hours.length > 0 ? (
                <List dense disablePadding>
                  {hours.map((h) => (
                    <ListItem key={h.day} divider>
                      <ListItemText
                        primary={h.day.charAt(0).toUpperCase() + h.day.slice(1)}
                        secondary={h.hours || 'Not specified'}
                        slotProps={{ primary: { sx: { fontWeight: 600, textTransform: 'capitalize' } } }}
                      />
                    </ListItem>
                  ))}
                </List>
              ) : (
                <NotReported what="Operating hours" />
              )}
            </TabSection>
          )}

          {/* 7 — Status */}
          {tabIndex === TAB.STATUS && (
            <TabSection title="Status" description="Operational state and activity counters.">
              <Grid container spacing={2}>
                <Grid item xs={12} md={6}>
                  <DetailField label="Operational status" value={<StatusBadge status={shop.status} />} />
                  <DetailField label="Products listed" value={shop.product_count} />
                </Grid>
                <Grid item xs={12} md={6}>
                  <DetailField label="Inventory records" value={shop.inventory_count} />
                  <DetailField label="Inventory freshness" value={shop.inventory_freshness} />
                  <DetailField label="Last inventory sync" value={fmtDateTime(shop.last_inventory_update)} />
                </Grid>
              </Grid>
              {shop.inventory_count == null && <NotReported what="An inventory record count" />}
            </TabSection>
          )}

          {/* 8 — Verification */}
          {tabIndex === TAB.VERIFICATION && (
            <TabSection title="Verification" description="Whether this business is verified to trade on the platform.">
              <DetailField label="Verification status" value={<StatusBadge status={shop.verification_status} />} />
              <DetailField label="Verified at" value={fmtDateTime(shop.verified_at)} />
              <DetailField label="Verified by" value={shop.verified_by} />
              {shop.rejection_reason && (
                <Alert severity="warning" sx={{ mt: 2 }}>
                  Rejection reason: {shop.rejection_reason}
                </Alert>
              )}
              {shop.verification_status === 'PENDING' && (
                <Alert severity="info" sx={{ mt: 2 }}>
                  This business is awaiting verification. Approve or reject it from the Businesses
                  list.
                </Alert>
              )}
            </TabSection>
          )}

          {/* 9 — Documents */}
          {tabIndex === TAB.DOCUMENTS && (
            <Box>
              <ListState
                isError={docsError}
                unavailable={!!documents?.unavailable}
                isEmpty={(documents?.items?.length ?? 0) === 0}
                emptyMessage="No documents have been uploaded for this business."
                unavailableMessage="The shop documents endpoint is not published on this deployment."
                onRetry={() => refetchDocuments()}
                isRetrying={docsFetching}
              />
              {(documents?.items?.length ?? 0) > 0 && (
                <AdminDataGrid
                  rows={documents!.items as unknown as Record<string, unknown>[]}
                  columns={docColumns}
                  totalRows={documents!.total}
                  paginationModel={docPagination}
                  onPaginationModelChange={setDocPagination}
                  loading={docsLoading}
                  searchPlaceholder="Search documents..."
                  searchValue={docSearch}
                  onSearchChange={setDocSearch}
                  onRefresh={() => refetchDocuments()}
                />
              )}
            </Box>
          )}

          {/* 10 — Products */}
          {tabIndex === TAB.PRODUCTS && (
            <Box>
              <ListState
                isError={productsError}
                unavailable={!!shopProducts?.unavailable}
                isEmpty={(shopProducts?.items?.length ?? 0) === 0}
                emptyMessage="This business has no products listed."
                unavailableMessage="Shop-scoped product listing is not published on this deployment."
                onRetry={() => refetchProducts()}
                isRetrying={productsFetching}
              />
              {(shopProducts?.items?.length ?? 0) > 0 && (
                <AdminDataGrid
                  rows={shopProducts!.items as Record<string, unknown>[]}
                  columns={productColumns}
                  totalRows={shopProducts!.total}
                  paginationModel={docPagination}
                  onPaginationModelChange={setDocPagination}
                  loading={productsLoading}
                  searchPlaceholder="Search products..."
                  searchValue={docSearch}
                  onSearchChange={setDocSearch}
                  onRefresh={() => refetchProducts()}
                />
              )}
            </Box>
          )}

          {/* 11 — Inventory (real drill-down) */}
          {tabIndex === TAB.INVENTORY && (
            <AdminDataGrid
              rows={(shopInventory?.items || []) as unknown as Record<string, unknown>[]}
              columns={invColumns}
              totalRows={shopInventory?.total ?? 0}
              paginationModel={invPagination}
              onPaginationModelChange={setInvPagination}
              loading={invLoading}
              error={invError}
              errorMessage="Inventory could not be loaded. The request failed — retry, and escalate if it keeps failing."
              searchPlaceholder="Search shop inventory..."
              searchValue={invSearch}
              onSearchChange={setInvSearch}
              onRefresh={() => refetchInventory()}
            />
          )}

          {/* 12 — Pricing */}
          {tabIndex === TAB.PRICING && (
            <Box>
              <ListState
                isError={priceError}
                unavailable={!!pricing?.unavailable}
                isEmpty={(pricing?.items?.length ?? 0) === 0}
                emptyMessage="No shop-scoped prices are recorded for this business."
                unavailableMessage="The shop pricing endpoint is not published on this deployment."
                onRetry={() => refetchPricing()}
                isRetrying={priceFetching}
              />
              {(pricing?.items?.length ?? 0) > 0 && (
                <AdminDataGrid
                  rows={pricing!.items as unknown as Record<string, unknown>[]}
                  columns={priceColumns}
                  totalRows={pricing!.total}
                  paginationModel={pricePagination}
                  onPaginationModelChange={setPricePagination}
                  loading={priceLoading}
                  searchPlaceholder="Search prices..."
                  searchValue={priceSearch}
                  onSearchChange={setPriceSearch}
                  onRefresh={() => refetchPricing()}
                />
              )}
            </Box>
          )}

          {/* 13 — Offers */}
          {tabIndex === TAB.OFFERS && (
            <Box>
              <ListState
                isError={offersError}
                unavailable={!!shopOffers?.unavailable}
                isEmpty={(shopOffers?.items?.length ?? 0) === 0}
                emptyMessage="No offers are running for this business."
                unavailableMessage="Shop-scoped offers are not published on this deployment."
                onRetry={() => refetchOffers()}
                isRetrying={offersFetching}
              />
              {(shopOffers?.items?.length ?? 0) > 0 && (
                <AdminDataGrid
                  rows={shopOffers!.items as Record<string, unknown>[]}
                  columns={offerColumns}
                  totalRows={shopOffers!.total}
                  paginationModel={docPagination}
                  onPaginationModelChange={setDocPagination}
                  loading={offersLoading}
                  searchPlaceholder="Search offers..."
                  searchValue={docSearch}
                  onSearchChange={setDocSearch}
                  onRefresh={() => refetchOffers()}
                />
              )}
            </Box>
          )}

          {/* 14 — History (real drill-down) */}
          {tabIndex === TAB.HISTORY && (
            <AdminDataGrid
              rows={(auditLogs?.items || []) as unknown as Record<string, unknown>[]}
              columns={logColumns}
              totalRows={auditLogs?.total ?? 0}
              paginationModel={logPagination}
              onPaginationModelChange={setLogPagination}
              loading={logsLoading}
              error={logsError}
              errorMessage="The audit trail could not be loaded. The request failed — retry, and escalate if it keeps failing."
              searchPlaceholder="Search audit entries..."
              searchValue={logSearch}
              onSearchChange={setLogSearch}
              onRefresh={() => refetchLogs()}
            />
          )}
        </>
      )}
    </Box>
  );
}
