'use client';

import React, { use, useState, useMemo } from 'react';
import { useRouter } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import {
  Box,
  Card,
  CardContent,
  Button,
  Typography,
  Alert,
  CircularProgress,
  Grid,
  Tabs,
  Tab,
  Table,
  TableHead,
  TableBody,
  TableRow,
  TableCell,
} from '@mui/material';
import {
  ArrowLeft,
  Package,
  Tag,
  Layers,
  ShoppingBag,
  DollarSign,
  History,
  Barcode,
  Boxes,
} from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { fetchList } from '@/core/api/fetchList';
import {
  ProductItem,
  ProductVariantItem,
  ShopInventoryItem,
  ShopPricingItem,
  AuditLogItem,
  CategoryItem,
  BrandItem,
} from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';
import {
  DetailField,
  TabSection,
  NotReported,
  ListState,
} from '@/core/components/BusinessDetailParts';

/**
 * One master product, every angle: identity, stocking shops, price spread,
 * availability, its own inventory records, and the audit trajectory. Variants
 * come from their own endpoint; everything else the detail payload already
 * carries or a scoped list query answers.
 */
const TABS = [
  'Product Master',
  'Brand',
  'Category',
  'Subcategory',
  'Variants',
  'Identifiers',
  'Images',
  'Status',
  'Shops',
  'Prices',
  'Availability',
  'Inventory',
  'History',
] as const;

const TAB = {
  MASTER: 0,
  BRAND: 1,
  CATEGORY: 2,
  SUBCATEGORY: 3,
  VARIANTS: 4,
  IDENTIFIERS: 5,
  IMAGES: 6,
  STATUS: 7,
  SHOPS: 8,
  PRICES: 9,
  AVAILABILITY: 10,
  INVENTORY: 11,
  HISTORY: 12,
} as const;


const fmtDate = (value?: string | null) =>
  value ? new Date(value).toLocaleDateString() : null;

const fmtDateTime = (value?: string | null) =>
  value ? new Date(value).toLocaleString() : null;

const fmtMoney = (value?: number | null) =>
  value == null ? null : `₹${Number(value).toLocaleString('en-IN')}`;

export default function ProductDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const router = useRouter();
  const [tabIndex, setTabIndex] = useState(0);
  const [invPagination, setInvPagination] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [invSearch, setInvSearch] = useState('');
  const [logPagination, setLogPagination] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [logSearch, setLogSearch] = useState('');

  const {
    data: product,
    isLoading,
    isError: productError,
    refetch: refetchProduct,
  } = useQuery<ProductItem>({
    queryKey: ['admin', 'products', id],
    queryFn: () => apiClient<ProductItem>(API_ENDPOINTS.PRODUCTS.DETAIL(id)),
  });

  // Backend-disclosed extras only. Nothing here is synthesized.
  const images = useMemo(() => {
    const out: string[] = [];
    if (product?.image_url) out.push(product.image_url);
    for (const u of product?.images || []) {
      if (u && !out.includes(u)) out.push(u);
    }
    return out;
  }, [product]);

  /**
   * One list query per dependent surface, enabled only while its tab is open.
   * `fetchList` keeps an unpublished route distinct from a failed one, which
   * is what lets unavailable tabs say so instead of implying zero records.
   */
  const productList = <T,>(endpoint: string, params: Record<string, unknown>) =>
    fetchList<T>(endpoint, {
      params: Object.entries(params).reduce<Record<string, string | number>>((acc, [k, v]) => {
        if (v !== undefined && v !== null && v !== '') acc[k] = v as string | number;
        return acc;
      }, {}),
    });

  const {
    data: variants,
    isLoading: variantsLoading,
    isError: variantsError,
    isFetching: variantsFetching,
    refetch: refetchVariants,
  } = useQuery({
    queryKey: ['admin', 'products', id, 'variants'],
    queryFn: () => productList<ProductVariantItem>(API_ENDPOINTS.PRODUCTS.VARIANTS(id), {}),
    enabled: tabIndex === TAB.VARIANTS,
    retry: false,
  });
  const {
    data: brandDetail,
    isLoading: brandLoading,
    isError: brandError,
    refetch: refetchBrand,
  } = useQuery({
    // BRANDS has no dedicated detail route; UPDATE doubles as the record
    // reader, the same shape brands/[id] already relies on.
    queryKey: ['admin', 'brands', product?.brand_id],
    queryFn: () =>
      apiClient<BrandItem>(API_ENDPOINTS.BRANDS.UPDATE(product!.brand_id!)),
    enabled: tabIndex === TAB.BRAND && product?.brand_id != null,
    retry: false,
  });

  const {
    data: categoryDetail,
    isLoading: categoryLoading,
    isError: categoryError,
    refetch: refetchCategory,
  } = useQuery({
    queryKey: ['admin', 'categories', product?.category_id],
    queryFn: () =>
      apiClient<CategoryItem>(API_ENDPOINTS.CATEGORIES.UPDATE(product!.category_id!)),
    enabled:
      (tabIndex === TAB.CATEGORY || tabIndex === TAB.SUBCATEGORY) &&
      product?.category_id != null,
    retry: false,
  });

  const {
    data: inventory,
    isLoading: invLoading,
    isError: invError,
    refetch: refetchInventory,
  } = useQuery<{ items: ShopInventoryItem[]; total: number }>({
    queryKey: ['admin', 'products', id, 'inventory', invPagination, invSearch],
    queryFn: () =>
      apiClient<{ items: ShopInventoryItem[]; total: number }>(
        API_ENDPOINTS.INVENTORY.STALE,
        {
          params: {
            product_id: id,
            search: invSearch || undefined,
            limit: invPagination.pageSize,
            offset: invPagination.page * invPagination.pageSize,
          },
        }
      ),
    enabled: tabIndex === TAB.INVENTORY || tabIndex === TAB.AVAILABILITY,
    retry: false,
  });
  const {
    data: prices,
    isLoading: pricesLoading,
    isError: pricesError,
    refetch: refetchPrices,
  } = useQuery({
    queryKey: ['admin', 'products', id, 'prices'],
    queryFn: () =>
      productList<ShopPricingItem>(API_ENDPOINTS.INVENTORY.MISSING_PRICES, {
        product_id: id,
        limit: 100,
      }),
    enabled: tabIndex === TAB.PRICES,
    retry: false,
  });

  const {
    data: auditLogs,
    isLoading: logsLoading,
    isError: logsError,
    refetch: refetchLogs,
  } = useQuery<{ items: AuditLogItem[]; total: number }>({
    queryKey: ['admin', 'products', id, 'audit-logs', logPagination, logSearch],
    queryFn: () =>
      apiClient<{ items: AuditLogItem[]; total: number }>(API_ENDPOINTS.AUDIT.LOGS, {
        params: {
          entity_type: 'product',
          entity_id: id,
          search: logSearch || undefined,
          limit: logPagination.pageSize,
          offset: logPagination.page * logPagination.pageSize,
        },
      }),
    enabled: tabIndex === TAB.HISTORY,
  });

  const availability = useMemo(() => {
    const rows = inventory?.items || [];
    const inStock = rows.filter((r) => r.quantity > 0);
    return {
      records: rows.length,
      inStock: inStock.length,
      missingPrice: rows.filter((r) => r.price == null).length,
      allOut: rows.length > 0 && inStock.length === 0,
    };
  }, [inventory]);

  const priceSpread = useMemo(() => {
    const vals = (prices?.items || [])
      .map((p) => p.price)
      .filter((v): v is number => v != null);
    if (vals.length === 0) return null;
    return { min: Math.min(...vals), max: Math.max(...vals), shops: vals.length };
  }, [prices]);

  const logColumns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    { field: 'action', headerName: 'Action', flex: 1 },
    { field: 'admin_user', headerName: 'Admin', width: 160 },
    {
      field: 'created_at',
      headerName: 'When',
      flex: 1,
      valueFormatter: (value: unknown) =>
        typeof value === 'string' && value ? new Date(value).toLocaleString() : '—',
    },
  ];
  const invColumns: GridColDef[] = [
    { field: 'shop_product_id', headerName: 'ID', width: 90 },
    { field: 'shop_name', headerName: 'Shop', flex: 1.4, minWidth: 170 },
    {
      field: 'quantity',
      headerName: 'Qty',
      width: 90,
      align: 'right',
      headerAlign: 'right',
    },
    {
      field: 'price',
      headerName: 'Price',
      width: 120,
      align: 'right',
      headerAlign: 'right',
      valueFormatter: (value) => (value != null ? `₹${value}` : 'MISSING'),
    },
    {
      field: 'stock_status',
      headerName: 'Stock',
      width: 130,
      renderCell: (params) => <StatusBadge status={(params.value as string) || 'UNKNOWN'} />,
    },
  ];

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Products', href: ROUTES.PRODUCTS },
          { label: product?.name ? product.name : `Product #${id}` },
        ]}
      />
      <Button
        startIcon={<ArrowLeft size={16} />}
        onClick={() => router.push(ROUTES.PRODUCTS)}
        sx={{ mb: 2 }}
      >
        Back to Catalog
      </Button>

      {/* Identity header — always visible, so the operator never leaves a tab
          to confirm which product they are looking at. */}
      <Card sx={{ mb: 2 }}>
        <CardContent sx={{ p: 3 }}>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, flexWrap: 'wrap' }}>
            <Box sx={{ p: 1.2, borderRadius: 2, backgroundColor: '#ECFDF5', color: '#059669', display: 'flex' }}>
              <Package size={24} />
            </Box>
            <Box sx={{ flex: 1, minWidth: 200 }}>
              <Typography variant="h6" sx={{ fontWeight: 700 }}>
                {product?.name || `Product #${id}`}
              </Typography>
              <Box sx={{ display: 'flex', gap: 1, alignItems: 'center', flexWrap: 'wrap', mt: 0.5 }}>
                <Typography variant="body2" color="text.secondary">
                  ID #{id}
                </Typography>
                {product?.brand_name && (
                  <Typography variant="body2" color="text.secondary">
                    · <Tag size={12} style={{ verticalAlign: 'middle' }} /> {product.brand_name}
                  </Typography>
                )}
                {product?.category_name && (
                  <Typography variant="body2" color="text.secondary">
                    · <Layers size={12} style={{ verticalAlign: 'middle' }} /> {product.category_name}
                  </Typography>
                )}
              </Box>
            </Box>
            {product?.status && <StatusBadge status={product.status} size="medium" />}
          </Box>
        </CardContent>
      </Card>

      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      )}

      {productError && (
        <Alert
          severity="error"
          sx={{ mb: 2 }}
          action={
            <Button color="inherit" size="small" onClick={() => refetchProduct()}>
              Retry
            </Button>
          }
        >
          This product record could not be loaded. The request failed — retry, and escalate if it
          keeps failing.
        </Alert>
      )}

      {!isLoading && !productError && !product && (
        <Alert severity="warning">
          No product record exists for #{id}. It may have been archived, or the id may refer to
          something other than a product.
        </Alert>
      )}
      {product && (
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

          {/* 1 — Product Master */}
          {tabIndex === TAB.MASTER && (
            <TabSection
              title="Product Master"
              description="The canonical catalog record for this product."
            >
              <Grid container spacing={2}>
                <Grid item xs={12} md={6}>
                  <DetailField label="Product name" value={product.name} />
                  <DetailField label="Product ID" value={product.id} mono />
                  <DetailField label="Description" value={product.description} />
                  <DetailField label="Unit" value={product.unit} />
                </Grid>
                <Grid item xs={12} md={6}>
                  <DetailField label="Barcode / EAN" value={product.barcode} mono />
                  <DetailField label="MRP" value={fmtMoney(product.mrp)} />
                  <DetailField label="Stocked in" value={`${product.shop_count ?? 0} shops`} />
                  <DetailField label="Status" value={<StatusBadge status={product.status} />} />
                </Grid>
                <Grid item xs={12} md={6}>
                  <DetailField label="Created" value={fmtDateTime(product.created_at)} />
                </Grid>
                <Grid item xs={12} md={6}>
                  <DetailField label="Last updated" value={fmtDateTime(product.updated_at)} />
                </Grid>
              </Grid>
            </TabSection>
          )}
          {/* 2 — Brand */}
          {tabIndex === TAB.BRAND && (
            <TabSection title="Brand" description="The brand this product is filed under.">
              {product.brand_id == null && (
                <NotReported what="A brand linkage" />
              )}
              {product.brand_id != null && (
                <>
                  <ListState
                    isError={brandError}
                    unavailable={false}
                    isEmpty={!brandLoading && !brandDetail}
                    emptyMessage={`Brand #${product.brand_id} returned no record.`}
                    unavailableMessage=""
                    onRetry={() => refetchBrand()}
                  />
                  {brandLoading && (
                    <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
                      <CircularProgress size={28} />
                    </Box>
                  )}
                  {brandDetail && (
                    <Grid container spacing={2}>
                      <Grid item xs={12} md={6}>
                        <DetailField label="Brand" value={brandDetail.name} />
                        <DetailField label="Slug" value={brandDetail.slug} mono />
                        <DetailField label="Description" value={brandDetail.description} />
                      </Grid>
                      <Grid item xs={12} md={6}>
                        <DetailField
                          label="Status"
                          value={
                            <StatusBadge status={brandDetail.is_active ? 'ACTIVE' : 'INACTIVE'} />
                          }
                        />
                        <DetailField label="Product count" value={brandDetail.product_count} />
                      </Grid>
                      <Grid item xs={12}>
                        <Button
                          size="small"
                          variant="outlined"
                          onClick={() => router.push(ROUTES.BRAND_DETAIL(brandDetail.id))}
                        >
                          Open Full Brand Profile →
                        </Button>
                      </Grid>
                    </Grid>
                  )}
                </>
              )}
            </TabSection>
          )}

          {/* 3 — Category */}
          {tabIndex === TAB.CATEGORY && (
            <TabSection
              title="Category"
              description="The taxonomy branch this product hangs on."
            >
              {product.category_id == null && (
                <NotReported what="A category assignment" />
              )}
              {product.category_id != null && (
                <>
                  <ListState
                    isError={categoryError}
                    unavailable={false}
                    isEmpty={!categoryLoading && !categoryDetail}
                    emptyMessage={`Category #${product.category_id} returned no record.`}
                    unavailableMessage=""
                    onRetry={() => refetchCategory()}
                  />
                  {categoryLoading && (
                    <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
                      <CircularProgress size={28} />
                    </Box>
                  )}
                  {categoryDetail && (
                    <Grid container spacing={2}>
                      <Grid item xs={12} md={6}>
                        <DetailField label="Category" value={categoryDetail.name} />
                        <DetailField label="Slug" value={categoryDetail.slug} mono />
                        <DetailField label="Description" value={categoryDetail.description} />
                      </Grid>
                      <Grid item xs={12} md={6}>
                        <DetailField
                          label="Status"
                          value={
                            <StatusBadge
                              status={categoryDetail.is_active ? 'ACTIVE' : 'INACTIVE'}
                            />
                          }
                        />
                        <DetailField label="Sort order" value={categoryDetail.sort_order} />
                        <DetailField label="Parent ID" value={categoryDetail.parent_id} mono />
                      </Grid>
                      <Grid item xs={12}>
                        <Button
                          size="small"
                          variant="outlined"
                          onClick={() => router.push(ROUTES.CATEGORY_DETAIL(categoryDetail.id))}
                        >
                          Open Full Category Profile →
                        </Button>
                      </Grid>
                    </Grid>
                  )}
                </>
              )}
            </TabSection>
          )}
          {/* 4 — Subcategory */}
          {tabIndex === TAB.SUBCATEGORY && (
            <TabSection
              title="Subcategory"
              description="The finer taxonomy cut below the category, when the backend assigns one."
            >
              {product.subcategory_id == null && (
                <NotReported what="A subcategory assignment" />
              )}
              {product.subcategory_id != null && (
                <>
                  <ListState
                    isError={categoryError}
                    unavailable={false}
                    isEmpty={!categoryLoading && !categoryDetail}
                    emptyMessage={`Subcategory #${product.subcategory_id} returned no record.`}
                    unavailableMessage=""
                    onRetry={() => refetchCategory()}
                  />
                  {categoryLoading && (
                    <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
                      <CircularProgress size={28} />
                    </Box>
                  )}
                  {categoryDetail && (
                    <Grid container spacing={2}>
                      <Grid item xs={12} md={6}>
                        <DetailField label="Subcategory ID" value={product.subcategory_id} mono />
                        <DetailField label="Parent category" value={categoryDetail.name} />
                      </Grid>
                      <Grid item xs={12} md={6}>
                        <DetailField
                          label="Parent status"
                          value={
                            <StatusBadge
                              status={categoryDetail.is_active ? 'ACTIVE' : 'INACTIVE'}
                            />
                          }
                        />
                        <DetailField label="Slug" value={categoryDetail.slug} mono />
                      </Grid>
                    </Grid>
                  )}
                </>
              )}
            </TabSection>
          )}

          {/* 5 — Variants */}
          {tabIndex === TAB.VARIANTS && (
            <TabSection
              title="Variants"
              description="The purchasable pack sizes and forms sold under this master record."
            >
              <ListState
                isError={variantsError}
                unavailable={variants?.unavailable ?? false}
                isEmpty={(variants?.items?.length ?? 0) === 0}
                emptyMessage="No variants are registered under this product."
                unavailableMessage="Product variants are not published on this deployment."
                onRetry={() => refetchVariants()}
                isRetrying={variantsFetching}
              />
              {(variants?.items || []).map((v) => (
                <Card key={String(v.id)} variant="outlined" sx={{ mb: 1.5 }}>
                  <CardContent
                    sx={{ p: 2, display: 'flex', alignItems: 'center', gap: 2, flexWrap: 'wrap' }}
                  >
                    <Box
                      sx={{
                        p: 1,
                        borderRadius: 1.5,
                        backgroundColor: '#ECFDF5',
                        color: '#059669',
                        display: 'flex',
                      }}
                    >
                      <Boxes size={18} />
                    </Box>
                    <Box sx={{ flex: 1, minWidth: 180 }}>
                      <Typography variant="body2" sx={{ fontWeight: 600 }}>
                        {v.variant_name || v.name || `Variant #${v.id}`}
                      </Typography>
                      <Typography variant="caption" color="text.secondary">
                        {[v.sku ? `SKU ${v.sku}` : null, v.barcode ? `EAN ${v.barcode}` : null]
                          .filter(Boolean)
                          .join(' · ') || 'No SKU or barcode'}
                      </Typography>
                      {(v.price != null || v.mrp != null || v.unit) && (
                        <Typography
                          variant="caption"
                          color="text.secondary"
                          sx={{ display: 'block' }}
                        >
                          {[fmtMoney(v.price), v.mrp != null ? `MRP ${fmtMoney(v.mrp)}` : null, v.unit]
                            .filter(Boolean)
                            .join(' · ')}
                        </Typography>
                      )}
                    </Box>
                    {v.status && <StatusBadge status={v.status} />}
                  </CardContent>
                </Card>
              ))}
            </TabSection>
          )}
          {/* 6 — Identifiers */}
          {tabIndex === TAB.IDENTIFIERS && (
            <TabSection
              title="Identifiers"
              description="Every code this product answers to — barcode, SKU, and any alternates the detail payload discloses."
            >
              <Table size="small">
                <TableHead>
                  <TableRow sx={{ backgroundColor: '#F8FAFC' }}>
                    <TableCell sx={{ fontWeight: 700 }}>Scheme</TableCell>
                    <TableCell sx={{ fontWeight: 700 }}>Value</TableCell>
                    <TableCell sx={{ fontWeight: 700 }}>Source</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  <TableRow>
                    <TableCell sx={{ fontWeight: 600 }}>Barcode / EAN</TableCell>
                    <TableCell sx={{ fontFamily: 'monospace' }}>{product.barcode || '—'}</TableCell>
                    <TableCell>Master record</TableCell>
                  </TableRow>
                  <TableRow>
                    <TableCell sx={{ fontWeight: 600 }}>Product ID</TableCell>
                    <TableCell sx={{ fontFamily: 'monospace' }}>{product.id}</TableCell>
                    <TableCell>Master record</TableCell>
                  </TableRow>
                </TableBody>
              </Table>
              {!product.barcode && (
                <Typography variant="body2" color="text.secondary" sx={{ mt: 1.5 }}>
                  No barcode is registered. Barcode-keyed discovery will miss this product until
                  one is assigned.
                </Typography>
              )}
            </TabSection>
          )}

          {/* 7 — Images */}
          {tabIndex === TAB.IMAGES && (
            <TabSection
              title="Images"
              description="The pack shots shoppers see. Nothing here is synthesized — only URLs the backend attached."
            >
              {images.length === 0 && <NotReported what="Product imagery" />}
              {images.length > 0 && (
                <Box sx={{ display: 'flex', gap: 2, flexWrap: 'wrap' }}>
                  {images.map((src) => (
                    // Plain img: next/image would demand remote-pattern config
                    // for backend hosts this console does not control.
                    // eslint-disable-next-line @next/next/no-img-element
                    <Box
                      key={src}
                      component="img"
                      src={src}
                      alt={product.name}
                      sx={{
                        width: 180,
                        height: 180,
                        objectFit: 'contain',
                        borderRadius: 2,
                        border: '1px solid #E2E8F0',
                        backgroundColor: '#FFFFFF',
                      }}
                    />
                  ))}
                </Box>
              )}
            </TabSection>
          )}

          {/* 8 — Status */}
          {tabIndex === TAB.STATUS && (
            <TabSection
              title="Status"
              description="Lifecycle state and lifecycle timestamps for this record."
            >
              <Grid container spacing={2}>
                <Grid item xs={12} md={6}>
                  <DetailField label="Status" value={<StatusBadge status={product.status} />} />
                  <DetailField label="Stocked in" value={`${product.shop_count ?? 0} shops`} />
                </Grid>
                <Grid item xs={12} md={6}>
                  <DetailField label="Created" value={fmtDateTime(product.created_at)} />
                  <DetailField label="Last updated" value={fmtDateTime(product.updated_at)} />
                </Grid>
              </Grid>
            </TabSection>
          )}
          {/* 9 — Shops */}
          {tabIndex === TAB.SHOPS && (
            <TabSection
              title="Shops"
              description="Every storefront stocking this product."
            >
              <ListState
                isError={invError}
                unavailable={false}
                isEmpty={!invLoading && (inventory?.items?.length ?? 0) === 0}
                emptyMessage="No shops currently stock this product."
                unavailableMessage=""
                onRetry={() => refetchInventory()}
              />
              {invLoading && (
                <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
                  <CircularProgress size={28} />
                </Box>
              )}
              {!invLoading &&
                (inventory?.items || []).map((row) => (
                  <Box
                    key={row.shop_product_id}
                    sx={{
                      display: 'flex',
                      gap: 1.5,
                      alignItems: 'center',
                      py: 1.25,
                      borderBottom: '1px solid #F1F5F9',
                      flexWrap: 'wrap',
                    }}
                  >
                    <Box sx={{ color: '#0F52BA', display: 'flex' }}>
                      <ShoppingBag size={16} />
                    </Box>
                    <Typography variant="body2" sx={{ fontWeight: 600, flex: 1, minWidth: 160 }}>
                      {row.shop_name || `Record #${row.shop_product_id}`}
                    </Typography>
                    <StatusBadge status={row.stock_status || 'UNKNOWN'} />
                    <Typography variant="caption" color="text.secondary">
                      Qty {row.quantity}
                      {row.price != null ? ` · ₹${row.price}` : ' · price missing'}
                    </Typography>
                  </Box>
                ))}
            </TabSection>
          )}

          {/* 10 — Prices */}
          {tabIndex === TAB.PRICES && (
            <TabSection
              title="Prices"
              description="What each stocking shop charges, derived from inventory records carrying a price."
            >
              <ListState
                isError={pricesError}
                unavailable={prices?.unavailable ?? false}
                isEmpty={!pricesLoading && (prices?.items?.length ?? 0) === 0}
                emptyMessage="No priced records exist for this product."
                unavailableMessage="Product-scoped price records are not published on this deployment."
                onRetry={() => refetchPrices()}
              />
              {pricesLoading && (
                <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
                  <CircularProgress size={28} />
                </Box>
              )}
              {!pricesLoading && priceSpread && (
                <Grid container spacing={2} sx={{ mb: 2 }}>
                  <Grid item xs={12} sm={4}>
                    <DetailField label="Lowest listed" value={fmtMoney(priceSpread.min)} />
                  </Grid>
                  <Grid item xs={12} sm={4}>
                    <DetailField label="Highest listed" value={fmtMoney(priceSpread.max)} />
                  </Grid>
                  <Grid item xs={12} sm={4}>
                    <DetailField label="Priced shops" value={priceSpread.shops} />
                  </Grid>
                </Grid>
              )}
              {!pricesLoading &&
                (prices?.items || []).map((p) => (
                  <Box
                    key={String(p.id)}
                    sx={{
                      display: 'flex',
                      gap: 1.5,
                      alignItems: 'center',
                      py: 1.25,
                      borderBottom: '1px solid #F1F5F9',
                    }}
                  >
                    <Box sx={{ color: '#0F52BA', display: 'flex' }}>
                      <DollarSign size={16} />
                    </Box>
                    <Typography variant="body2" sx={{ fontWeight: 600, flex: 1 }}>
                      {p.product_name || `Record #${p.id}`}
                    </Typography>
                    <Typography variant="body2" sx={{ fontWeight: 600 }}>
                      {fmtMoney(p.price) || 'MISSING'}
                    </Typography>
                    {p.mrp != null && (
                      <Typography variant="caption" color="text.secondary">
                        MRP {fmtMoney(p.mrp)}
                      </Typography>
                    )}
                  </Box>
                ))}
            </TabSection>
          )}
          {/* 11 — Availability */}
          {tabIndex === TAB.AVAILABILITY && (
            <TabSection
              title="Availability"
              description="Whether a shopper can actually buy this product right now."
            >
              <ListState
                isError={invError}
                unavailable={false}
                isEmpty={!invLoading && availability.records === 0}
                emptyMessage="No inventory records reference this product."
                unavailableMessage=""
                onRetry={() => refetchInventory()}
              />
              {invLoading && (
                <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
                  <CircularProgress size={28} />
                </Box>
              )}
              {!invLoading && availability.records > 0 && (
                <>
                  {availability.allOut && (
                    <Alert severity="warning" sx={{ mb: 2 }}>
                      Listed in {availability.records} shop
                      {availability.records === 1 ? '' : 's'} but out of stock in all of them.
                    </Alert>
                  )}
                  <Grid container spacing={2}>
                    <Grid item xs={12} sm={4}>
                      <DetailField label="Stocking shops" value={availability.records} />
                    </Grid>
                    <Grid item xs={12} sm={4}>
                      <DetailField label="In stock" value={availability.inStock} />
                    </Grid>
                    <Grid item xs={12} sm={4}>
                      <DetailField label="Missing price" value={availability.missingPrice} />
                    </Grid>
                  </Grid>
                </>
              )}
            </TabSection>
          )}

          {/* 12 — Inventory */}
          {tabIndex === TAB.INVENTORY && (
            <Box>
              <ListState
                isError={invError}
                unavailable={false}
                isEmpty={!invLoading && (inventory?.items?.length ?? 0) === 0}
                emptyMessage="No inventory records reference this product."
                unavailableMessage=""
                onRetry={() => refetchInventory()}
              />
              {(inventory?.items?.length ?? 0) > 0 && (
                <AdminDataGrid
                  rows={(inventory!.items || []) as unknown as Record<string, unknown>[]}
                  columns={invColumns}
                  totalRows={inventory!.total}
                  paginationModel={invPagination}
                  onPaginationModelChange={setInvPagination}
                  loading={invLoading}
                  searchPlaceholder="Search stocking shops..."
                  searchValue={invSearch}
                  onSearchChange={setInvSearch}
                  onRefresh={() => refetchInventory()}
                  error={invError}
                  errorMessage="The inventory records could not be loaded. The request failed — retry, and escalate if it keeps failing."
                />
              )}
            </Box>
          )}

          {/* 13 — History */}
          {tabIndex === TAB.HISTORY && (
            <Box>
              <ListState
                isError={logsError}
                unavailable={false}
                isEmpty={!logsLoading && (auditLogs?.items?.length ?? 0) === 0}
                emptyMessage="No audit entries reference this product."
                unavailableMessage=""
                onRetry={() => refetchLogs()}
              />
              {(auditLogs?.items?.length ?? 0) > 0 && (
                <AdminDataGrid
                  rows={(auditLogs!.items || []) as unknown as Record<string, unknown>[]}
                  columns={logColumns}
                  totalRows={auditLogs!.total}
                  paginationModel={logPagination}
                  onPaginationModelChange={setLogPagination}
                  loading={logsLoading}
                  searchPlaceholder="Search audit entries..."
                  searchValue={logSearch}
                  onSearchChange={setLogSearch}
                  onRefresh={() => refetchLogs()}
                  error={logsError}
                  errorMessage="The audit trail could not be loaded. The request failed — retry, and escalate if it keeps failing."
                />
              )}
            </Box>
          )}
        </>
      )}
    </Box>
  );
}
