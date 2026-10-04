'use client';

import React, { useState } from 'react';
import { useRouter } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import {
  Box,
  Typography,
  Grid,
  Card,
  CardContent,
  CardActionArea,
  Button,
  ButtonGroup,
  Alert,
  CircularProgress,
  Chip,
} from '@mui/material';
import {
  Users,
  Store,
  Package,
  Warehouse,
  AlertTriangle,
  Clock,
  HelpCircle,
  TrendingUp,
  RefreshCw,
} from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { DashboardMetrics } from '@/core/types/admin';
import { BarChart } from '@mui/x-charts/BarChart';

export default function DashboardPage() {
  const router = useRouter();
  const [dateRange, setDateRange] = useState<'7' | '30' | '90'>('30');

  const { data: metrics, isLoading, isError, error, refetch, isFetching } = useQuery<DashboardMetrics>({
    queryKey: ['admin', 'dashboard', 'metrics'],
    queryFn: () => apiClient<DashboardMetrics>(API_ENDPOINTS.DASHBOARD.METRICS),
  });

  return (
    <Box>
      {/* Page Header */}
      <Box
        sx={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: { xs: 'flex-start', sm: 'center' },
          flexDirection: { xs: 'column', sm: 'row' },
          gap: 2,
          mb: 3,
        }}
      >
        <Box>
          <Typography variant="h5" sx={{ fontWeight: 700 }}>
            Operational Control Center
          </Typography>
          <Typography variant="body2" color="text.secondary">
            Platform-wide real-time metrics, active queues, and operational health.
          </Typography>
        </Box>

        {/* Date Filter & Refresh */}
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
          <ButtonGroup size="small" variant="outlined">
            <Button
              variant={dateRange === '7' ? 'contained' : 'outlined'}
              onClick={() => setDateRange('7')}
            >
              7D
            </Button>
            <Button
              variant={dateRange === '30' ? 'contained' : 'outlined'}
              onClick={() => setDateRange('30')}
            >
              30D
            </Button>
            <Button
              variant={dateRange === '90' ? 'contained' : 'outlined'}
              onClick={() => setDateRange('90')}
            >
              90D
            </Button>
          </ButtonGroup>

          <Button
            size="small"
            variant="outlined"
            onClick={() => refetch()}
            disabled={isFetching}
            startIcon={isFetching ? <CircularProgress size={14} /> : <RefreshCw size={14} />}
          >
            Refresh
          </Button>
        </Box>
      </Box>

      {/* Error State */}
      {isError && (
        <Alert severity="error" sx={{ mb: 3 }}>
          Failed to load operational metrics: {error instanceof Error ? error.message : 'Unknown error'}
        </Alert>
      )}

      {/* Top Primary KPIs */}
      <Grid container spacing={2.5} sx={{ mb: 3 }}>
        {/* Customers */}
        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardActionArea onClick={() => router.push('/customers')}>
              <CardContent sx={{ p: 2.5 }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                  <Box>
                    <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 600 }}>
                      TOTAL CUSTOMERS
                    </Typography>
                    <Typography variant="h5" sx={{ fontWeight: 800, mt: 0.5 }}>
                      {isLoading ? '...' : (metrics?.total_customers ?? 0).toLocaleString()}
                    </Typography>
                  </Box>
                  <Box sx={{ p: 1, backgroundColor: '#EFF6FF', borderRadius: 1.5, color: '#3B82F6' }}>
                    <Users size={22} />
                  </Box>
                </Box>
                <Typography variant="caption" color="primary" sx={{ mt: 1, display: 'block', fontWeight: 600 }}>
                  View All Customers →
                </Typography>
              </CardContent>
            </CardActionArea>
          </Card>
        </Grid>

        {/* Shops */}
        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardActionArea onClick={() => router.push('/businesses')}>
              <CardContent sx={{ p: 2.5 }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                  <Box>
                    <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 600 }}>
                      ACTIVE SHOPS
                    </Typography>
                    <Typography variant="h5" sx={{ fontWeight: 800, mt: 0.5 }}>
                      {isLoading ? '...' : `${metrics?.active_shops ?? 0} / ${metrics?.total_shops ?? 0}`}
                    </Typography>
                  </Box>
                  <Box sx={{ p: 1, backgroundColor: '#ECFDF5', borderRadius: 1.5, color: '#10B981' }}>
                    <Store size={22} />
                  </Box>
                </Box>
                <Typography variant="caption" color="success.main" sx={{ mt: 1, display: 'block', fontWeight: 600 }}>
                  Manage Businesses →
                </Typography>
              </CardContent>
            </CardActionArea>
          </Card>
        </Grid>

        {/* Products */}
        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardActionArea onClick={() => router.push('/products')}>
              <CardContent sx={{ p: 2.5 }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                  <Box>
                    <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 600 }}>
                      CATALOG PRODUCTS
                    </Typography>
                    <Typography variant="h5" sx={{ fontWeight: 800, mt: 0.5 }}>
                      {isLoading ? '...' : (metrics?.total_products ?? 0).toLocaleString()}
                    </Typography>
                  </Box>
                  <Box sx={{ p: 1, backgroundColor: '#FAF5FF', borderRadius: 1.5, color: '#A855F7' }}>
                    <Package size={22} />
                  </Box>
                </Box>
                <Typography variant="caption" color="secondary" sx={{ mt: 1, display: 'block', fontWeight: 600 }}>
                  Browse Master Catalog →
                </Typography>
              </CardContent>
            </CardActionArea>
          </Card>
        </Grid>

        {/* Inventory Records */}
        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardActionArea onClick={() => router.push('/inventory')}>
              <CardContent sx={{ p: 2.5 }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                  <Box>
                    <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 600 }}>
                      INVENTORY RECORDS
                    </Typography>
                    <Typography variant="h5" sx={{ fontWeight: 800, mt: 0.5 }}>
                      {isLoading ? '...' : (metrics?.total_inventory_records ?? 0).toLocaleString()}
                    </Typography>
                  </Box>
                  <Box sx={{ p: 1, backgroundColor: '#FFFBEB', borderRadius: 1.5, color: '#F59E0B' }}>
                    <Warehouse size={22} />
                  </Box>
                </Box>
                <Typography variant="caption" color="warning.main" sx={{ mt: 1, display: 'block', fontWeight: 600 }}>
                  Inventory Freshness →
                </Typography>
              </CardContent>
            </CardActionArea>
          </Card>
        </Grid>
      </Grid>

      {/* Operational Triage Queues (Section 2: Drill-down actions) */}
      <Typography variant="subtitle2" sx={{ mb: 1.5, color: 'text.secondary', fontWeight: 700 }}>
        OPERATIONAL QUEUES & DRILL-DOWNS
      </Typography>

      <Grid container spacing={2.5} sx={{ mb: 3 }}>
        {/* Pending Verification */}
        <Grid item xs={12} sm={6} md={3}>
          <Card sx={{ borderLeft: '4px solid #F59E0B' }}>
            <CardActionArea onClick={() => router.push('/verification')}>
              <CardContent sx={{ p: 2 }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <Typography variant="body2" sx={{ fontWeight: 600 }}>
                    Pending Verification
                  </Typography>
                  <Chip
                    label={metrics?.pending_verification ?? 0}
                    color={(metrics?.pending_verification ?? 0) > 0 ? 'warning' : 'default'}
                    size="small"
                  />
                </Box>
                <Typography variant="caption" color="text.secondary" sx={{ mt: 0.5, display: 'block' }}>
                  Merchant onboarding & documents
                </Typography>
              </CardContent>
            </CardActionArea>
          </Card>
        </Grid>

        {/* Stale Inventory */}
        <Grid item xs={12} sm={6} md={3}>
          <Card sx={{ borderLeft: '4px solid #EF4444' }}>
            <CardActionArea onClick={() => router.push('/inventory?filter=stale')}>
              <CardContent sx={{ p: 2 }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <Typography variant="body2" sx={{ fontWeight: 600 }}>
                    Stale Inventory
                  </Typography>
                  <Chip
                    label={metrics?.stale_inventory_count ?? 0}
                    color={(metrics?.stale_inventory_count ?? 0) > 0 ? 'error' : 'default'}
                    size="small"
                  />
                </Box>
                <Typography variant="caption" color="text.secondary" sx={{ mt: 0.5, display: 'block' }}>
                  Records older than 48 hours
                </Typography>
              </CardContent>
            </CardActionArea>
          </Card>
        </Grid>

        {/* Product Approvals */}
        <Grid item xs={12} sm={6} md={3}>
          <Card sx={{ borderLeft: '4px solid #3B82F6' }}>
            <CardActionArea onClick={() => router.push('/products/approvals')}>
              <CardContent sx={{ p: 2 }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <Typography variant="body2" sx={{ fontWeight: 600 }}>
                    Pending Approvals
                  </Typography>
                  <Chip
                    label={metrics?.pending_approvals ?? 0}
                    color={(metrics?.pending_approvals ?? 0) > 0 ? 'primary' : 'default'}
                    size="small"
                  />
                </Box>
                <Typography variant="caption" color="text.secondary" sx={{ mt: 0.5, display: 'block' }}>
                  Shopkeeper custom listings
                </Typography>
              </CardContent>
            </CardActionArea>
          </Card>
        </Grid>

        {/* Open Complaints */}
        <Grid item xs={12} sm={6} md={3}>
          <Card sx={{ borderLeft: '4px solid #EC4899' }}>
            <CardActionArea onClick={() => router.push('/support')}>
              <CardContent sx={{ p: 2 }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <Typography variant="body2" sx={{ fontWeight: 600 }}>
                    Support Complaints
                  </Typography>
                  <Chip
                    label={metrics?.open_complaints ?? 0}
                    color={(metrics?.open_complaints ?? 0) > 0 ? 'error' : 'default'}
                    size="small"
                  />
                </Box>
                <Typography variant="caption" color="text.secondary" sx={{ mt: 0.5, display: 'block' }}>
                  Unresolved customer/merchant tickets
                </Typography>
              </CardContent>
            </CardActionArea>
          </Card>
        </Grid>
      </Grid>
      {/* Popular Categories — MUI X Charts (MEASURE) */}
      <Card sx={{ mb: 3 }}>
        <CardContent sx={{ p: 3 }}>
          <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 0.5 }}>
            Popular Categories by Search Demand
          </Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
            Top taxonomy nodes driving discovery this period. Click a bar&apos;s category to audit its catalog.
          </Typography>
          {isLoading ? (
            <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
              <CircularProgress />
            </Box>
          ) : (metrics?.popular_categories?.length ?? 0) > 0 ? (
            <Box sx={{ width: '100%', overflowX: 'auto' }}>
              <BarChart
                height={280}
                xAxis={[{ scaleType: 'band', data: metrics!.popular_categories.map((c) => c.name) }]}
                series={[
                  {
                    data: metrics!.popular_categories.map((c) => c.count),
                    label: 'Searches',
                    color: '#0F52BA',
                  },
                ]}
                margin={{ top: 16, right: 16, bottom: 40, left: 48 }}
                slotProps={{
                  legend: { hidden: true },
                  bar: {
                    onClick: (event: React.MouseEvent<SVGRectElement>) => {
                      const idx = Number(event.currentTarget.getAttribute('data-series-index') ?? -1);
                      const cat = metrics?.popular_categories[idx];
                      if (cat) router.push(`/products?search=${encodeURIComponent(cat.name)}`);
                    },
                  },
                }}
              />
            </Box>
          ) : (
            <Typography variant="body2" color="text.secondary" sx={{ py: 4, textAlign: 'center' }}>
              No category demand data available yet.
            </Typography>
          )}
        </CardContent>
      </Card>
    </Box>
  );
}
