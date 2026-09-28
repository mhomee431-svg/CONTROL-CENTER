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
import { ArrowLeft, Store, MapPin, Tag, Calendar, Package } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { ShopItem } from '@/core/types/admin';
import { StatusBadge } from '@/core/components/StatusBadge';

export default function BusinessDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const resolvedParams = use(params);
  const router = useRouter();
  const shopId = resolvedParams.id;
  const [tabIndex, setTabIndex] = useState(0);

  const { data: shop, isLoading, isError } = useQuery<ShopItem>({
    queryKey: ['admin', 'shops', shopId],
    queryFn: () => apiClient<ShopItem>(API_ENDPOINTS.SHOPS.DETAIL(shopId)),
  });

  return (
    <Box>
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

          {/* Tab 1: Catalog */}
          {tabIndex === 1 && (
            <Card>
              <CardContent sx={{ p: 3 }}>
                <Typography variant="body2" color="text.secondary">
                  Showing active listings and synchronized SKU inventory for {shop.name}. Total active records: {shop.product_count}.
                </Typography>
              </CardContent>
            </Card>
          )}

          {/* Tab 2: Audit */}
          {tabIndex === 2 && (
            <Card>
              <CardContent sx={{ p: 3 }}>
                <Typography variant="body2" color="text.secondary">
                  Traceable administrative timeline and verification decisions for this merchant storefront.
                </Typography>
              </CardContent>
            </Card>
          )}
        </Box>
      )}
    </Box>
  );
}
