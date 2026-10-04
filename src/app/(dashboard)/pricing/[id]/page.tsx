'use client';

import React from 'react';
import { useRouter } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { Box, Card, CardContent, Button, Typography, Divider, Alert, CircularProgress, Grid } from '@mui/material';
import { ArrowLeft, DollarSign } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { StaleInventoryItem } from '@/core/types/admin';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';

interface PricingAnomaly extends Partial<StaleInventoryItem> {
  shop_product_id: number;
  product_name: string;
  shop_name: string;
  price?: number | null;
  mrp?: number | null;
}

export default function PricingDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = React.use(params);
  const router = useRouter();

  const { data, isLoading, isError } = useQuery<{ items: PricingAnomaly[] }>({
    queryKey: ['admin', 'pricing-anomalies', 'all'],
    queryFn: () =>
      apiClient<{ items: PricingAnomaly[] }>(API_ENDPOINTS.INVENTORY.MISSING_PRICES, {
        params: { limit: 250 },
      }),
  });

  const record = data?.items?.find((r) => String(r.shop_product_id) === String(id));

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Pricing', href: ROUTES.PRICING },
          { label: record?.product_name || `Record #${id}` },
        ]}
      />
      <Button startIcon={<ArrowLeft size={16} />} onClick={() => router.push(ROUTES.PRICING)} sx={{ mb: 2 }}>
        Back to Pricing
      </Button>

      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      )}
      {isError && <Alert severity="error">Could not load pricing record #{id}.</Alert>}
      {!isLoading && !record && <Alert severity="warning">Pricing record #{id} was not found.</Alert>}

      {record && (
        <Card>
          <CardContent sx={{ p: 3 }}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                <Box sx={{ p: 1.2, borderRadius: 2, backgroundColor: '#FFFBEB', color: '#F59E0B' }}>
                  <DollarSign size={24} />
                </Box>
                <Box>
                  <Typography variant="h6" sx={{ fontWeight: 700 }}>
                    {record.product_name}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    Record #{record.shop_product_id} · {record.shop_name}
                  </Typography>
                </Box>
              </Box>
              <StatusBadge status={record.price != null ? 'ACTIVE' : 'MISSING'} size="medium" />
            </Box>
            <Divider sx={{ my: 2 }} />
            <Grid container spacing={2}>
              <Grid item xs={12} sm={4}>
                <Typography variant="caption" color="text.secondary">
                  Listed Price
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {record.price != null ? `₹${record.price}` : 'MISSING'}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={4}>
                <Typography variant="caption" color="text.secondary">
                  MRP
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {record.mrp != null ? `₹${record.mrp}` : 'Not provided'}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={4}>
                <Typography variant="caption" color="text.secondary">
                  Stock Status
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {record.stock_status || 'Unknown'}
                </Typography>
              </Grid>
            </Grid>
            <Box sx={{ mt: 3 }}>
              <Button
                variant="outlined"
                onClick={() => router.push(ROUTES.INVENTORY_DETAIL(record.shop_product_id))}
              >
                Open Inventory Record →
              </Button>
            </Box>
          </CardContent>
        </Card>
      )}
    </Box>
  );
}
