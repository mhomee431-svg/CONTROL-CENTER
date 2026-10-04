'use client';

import React, { use, useState } from 'react';
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
  CircularProgress,
} from '@mui/material';
import { ArrowLeft, Store, MapPin, Tag, Calendar, Package, Warehouse, User } from 'lucide-react';
import Link from 'next/link';
import MuiLink from '@mui/material/Link';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { ShopItem } from '@/core/types/admin';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { ShopInventoryItem, AuditLogItem } from '@/core/types/admin';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';

export default function BusinessDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const resolvedParams = use(params);
  const router = useRouter();
  const shopId = resolvedParams.id;
  const [tabIndex, setTabIndex] = useState(0);
  const [invPagination, setInvPagination] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [logPagination, setLogPagination] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });

  const { data: shop, isLoading, isError } = useQuery<ShopItem>({
    queryKey: ['admin', 'shops', shopId],
    queryFn: () => apiClient<ShopItem>(API_ENDPOINTS.SHOPS.DETAIL(shopId)),
  });

  // Drill-down: this shop's inventory records
  const { data: shopInventory, isLoading: invLoading } = useQuery<{ items: ShopInventoryItem[]; total: number }>({
    queryKey: ['admin', 'shops', shopId, 'inventory', invPagination],
    queryFn: () =>
      apiClient<{ items: ShopInventoryItem[]; total: number }>(
        API_ENDPOINTS.INVENTORY.SHOP_INVENTORY(shopId),
        {
          params: {
            limit: invPagination.pageSize,
            offset: invPagination.page * invPagination.pageSize,
          },
        }
      ),
    enabled: tabIndex === 1,
  });

  // Drill-down: this shop's audit trail
  const { data: auditLogs, isLoading: logsLoading } = useQuery<{ items: AuditLogItem[]; total: number }>({
    queryKey: ['admin', 'shops', shopId, 'audit-logs', logPagination],
    queryFn: () =>
      apiClient<{ items: AuditLogItem[]; total: number }>(API_ENDPOINTS.AUDIT.LOGS, {
        params: {
          entity_type: 'shop',
          entity_id: shopId,
          limit: logPagination.pageSize,
          offset: logPagination.page * logPagination.pageSize,
        },
      }),
    enabled: tabIndex === 2,
  });

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
          { label: shop?.name ? shop.name : `Shop #${shopId}` },
        ]}
      />
      <Button
        startIcon={<ArrowLeft size={16} />}
        onClick={() => router.push('/businesses')}
        sx={{ mb: 2 }}
      >
        Back to Shops
      </Button>

      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      )}

      {isError && (
        <Alert severity="error" sx={{ mb: 3 }}>
          Could not load business details for Shop #{shopId}.
        </Alert>
      )}

      {shop && (
        <Box>
          {/* Header Card */}
          <Card sx={{ mb: 3 }}>
            <CardContent sx={{ p: 3 }}>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: 2 }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                  <Box
                    sx={{
                      width: 56,
                      height: 56,
                      borderRadius: 2,
                      backgroundColor: '#EFF6FF',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      color: 'primary.main',
                    }}
                  >
                    <Store size={28} />
                  </Box>
                  <Box>
                    <Typography variant="h5" sx={{ fontWeight: 700 }}>
                      {shop.name}
                    </Typography>
                    <Typography variant="body2" color="text.secondary">
                      Shop ID: #{shop.id} • Registered Owner ID: #{shop.owner_id}
                    </Typography>
                  </Box>
                </Box>

                <Box sx={{ display: 'flex', gap: 1.5, alignItems: 'center' }}>
                  <StatusBadge status={shop.status} size="medium" />
                  <StatusBadge status={shop.verification_status} size="medium" />
                </Box>
              </Box>

              <Divider sx={{ my: 2.5 }} />

              <Tabs value={tabIndex} onChange={(_, val) => setTabIndex(val)}>
                <Tab label="Overview & Profile" />
                <Tab label="Catalog & Inventory" />
                <Tab label="Audit & Activity" />
              </Tabs>
            </CardContent>
          </Card>

          {/* Tab 0: Overview */}
          {tabIndex === 0 && (
            <Grid container spacing={3}>
              <Grid item xs={12} md={6}>
                <Card>
                  <CardContent sx={{ p: 3 }}>
                    <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 2 }}>
                      Store Information
                    </Typography>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, mb: 2 }}>
                      <Tag size={16} color="#64748B" />
                      <Typography variant="body2" color="text.secondary">
                        Category:
                      </Typography>
                      <Typography variant="body2" sx={{ fontWeight: 600 }}>
                        {shop.category}
                      </Typography>
                    </Box>

                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, mb: 2 }}>
                      <MapPin size={16} color="#64748B" />
                      <Typography variant="body2" color="text.secondary">
                        Physical Location:
                      </Typography>
                      <Typography variant="body2" sx={{ fontWeight: 600 }}>
                        {shop.city}, {shop.state}
                      </Typography>
                    </Box>

                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
                      <Calendar size={16} color="#64748B" />
                      <Typography variant="body2" color="text.secondary">
                        Created On:
                      </Typography>
                      <Typography variant="body2" sx={{ fontWeight: 600 }}>
                        {new Date(shop.created_at).toLocaleString()}
                      </Typography>
                    </Box>
                  </CardContent>
                </Card>
              </Grid>

              <Grid item xs={12} md={6}>
                <Card>
                  <CardContent sx={{ p: 3 }}>
                    <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 2 }}>
                      Operational Metrics
                    </Typography>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, mb: 2 }}>
                      <Package size={16} color="#64748B" />
                      <Typography variant="body2" color="text.secondary">
                        Listed Products:
                      </Typography>
                      <Typography variant="body2" sx={{ fontWeight: 600 }}>
                        {shop.product_count} products
                      </Typography>
                    </Box>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, mb: 2 }}>
                      <User size={16} color="#64748B" />
                      <Typography variant="body2" color="text.secondary">
                        Shopkeeper:
                      </Typography>
                      <MuiLink
                        component={Link}
                        href={`/shopkeepers?highlight=${shop.owner_id}`}
                        underline="hover"
                        sx={{ fontWeight: 600 }}
                      >
                        {shop.owner_name || `#${shop.owner_id}`} →
                      </MuiLink>
                    </Box>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
                      <Store size={16} color="#64748B" />
                      <Typography variant="body2" color="text.secondary">
                        Inventory Freshness:
                      </Typography>
                      <StatusBadge status={shop.inventory_freshness || 'FRESH'} />
                    </Box>
                  </CardContent>
                </Card>
              </Grid>
            </Grid>
          )}

          {/* Tab 1: Catalog & Inventory (real drill-down) */}
          {tabIndex === 1 && (
            <Box>
              <Box sx={{ mb: 2, display: 'flex', alignItems: 'center', gap: 1.5 }}>
                <Warehouse size={18} color="#F59E0B" />
                <Typography variant="body2" color="text.secondary">
                  Synchronized SKU inventory for <strong>{shop.name}</strong>. Click a record to open its full
                  Inventory Record (history → shop → shopkeeper).
                </Typography>
              </Box>
              <AdminDataGrid
                rows={(shopInventory?.items || []) as unknown as Record<string, unknown>[]}
                columns={invColumns}
                totalRows={shopInventory?.total ?? 0}
                paginationModel={invPagination}
                onPaginationModelChange={setInvPagination}
                loading={invLoading}
                searchPlaceholder="Search shop inventory..."
                onRefresh={() => void shopInventory}
                onRowClick={(params) =>
                  router.push(`/inventory/${params.row.shop_product_id ?? params.id}?from=shop`)
                }
              />
            </Box>
          )}

          {/* Tab 2: Audit (real drill-down) */}
          {tabIndex === 2 && (
            <Box>
              <Box sx={{ mb: 2 }}>
                <Typography variant="body2" color="text.secondary">
                  Traceable administrative timeline and verification decisions for <strong>{shop.name}</strong>.
                </Typography>
              </Box>
              <AdminDataGrid
                rows={(auditLogs?.items || []) as unknown as Record<string, unknown>[]}
                columns={logColumns}
                totalRows={auditLogs?.total ?? 0}
                paginationModel={logPagination}
                onPaginationModelChange={setLogPagination}
                loading={logsLoading}
                searchPlaceholder="Search audit entries..."
                onRefresh={() => void auditLogs}
              />
            </Box>
          )}
        </Box>
      )}
    </Box>
  );
}
