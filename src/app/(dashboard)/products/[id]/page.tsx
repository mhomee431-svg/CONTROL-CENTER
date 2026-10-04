'use client';

import React from 'react';
import { useRouter } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { Box, Card, CardContent, Button, Typography, Divider, Alert, CircularProgress, Grid } from '@mui/material';
import { ArrowLeft, Package } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { ProductItem } from '@/core/types/admin';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';

export default function ProductDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = React.use(params);
  const router = useRouter();

  const { data: product, isLoading, isError } = useQuery<ProductItem>({
    queryKey: ['admin', 'products', id],
    queryFn: () => apiClient<ProductItem>(API_ENDPOINTS.PRODUCTS.DETAIL(id)),
  });

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Products', href: ROUTES.PRODUCTS },
          { label: product?.name || `Product #${id}` },
        ]}
      />
      <Button startIcon={<ArrowLeft size={16} />} onClick={() => router.push(ROUTES.PRODUCTS)} sx={{ mb: 2 }}>
        Back to Catalog
      </Button>

      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      )}
      {isError && <Alert severity="error">Could not load product #{id}.</Alert>}

      {product && (
        <Card>
          <CardContent sx={{ p: 3 }}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                <Box sx={{ p: 1.2, borderRadius: 2, backgroundColor: '#ECFDF5', color: '#10B981' }}>
                  <Package size={24} />
                </Box>
                <Box>
                  <Typography variant="h6" sx={{ fontWeight: 700 }}>
                    {product.name}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    Product ID: #{product.id}
                  </Typography>
                </Box>
              </Box>
              <StatusBadge status={product.status} size="medium" />
            </Box>
            <Divider sx={{ my: 2 }} />
            <Grid container spacing={2}>
              <Field label="Brand" value={product.brand_name || 'Generic / Unbranded'} />
              <Field label="Category" value={product.category_name || 'Unassigned'} />
              <Field label="Barcode / EAN" value={product.barcode || 'Not provided'} />
              <Field label="Stocked In" value={`${product.shop_count ?? 0} shops`} />
              <Field
                label="Created"
                value={product.created_at ? new Date(product.created_at).toLocaleString() : 'N/A'}
              />
              <Field
                label="Last Updated"
                value={product.updated_at ? new Date(product.updated_at).toLocaleString() : 'N/A'}
              />
            </Grid>
          </CardContent>
        </Card>
      )}
    </Box>
  );
}

function Field({ label, value }: { label: string; value: string }) {
  return (
    <Grid item xs={12} sm={6} md={4}>
      <Typography variant="caption" color="text.secondary">
        {label}
      </Typography>
      <Typography variant="body2" sx={{ fontWeight: 600 }}>
        {value}
      </Typography>
    </Grid>
  );
}
