'use client';

import React from 'react';
import { useRouter } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { Box, Card, CardContent, Button, Typography, Divider, Alert, CircularProgress, Grid } from '@mui/material';
import { ArrowLeft, Tag } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { BrandItem } from '@/core/types/admin';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';

export default function BrandDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = React.use(params);
  const router = useRouter();

  const { data, isLoading, isError } = useQuery<{ items: BrandItem[] }>({
    queryKey: ['admin', 'brands'],
    queryFn: () => apiClient<{ items: BrandItem[] }>(API_ENDPOINTS.BRANDS.LIST),
  });

  const brand = data?.items?.find((b) => String(b.id) === String(id));

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Brands', href: ROUTES.BRANDS },
          { label: brand?.name || `Brand #${id}` },
        ]}
      />
      <Button startIcon={<ArrowLeft size={16} />} onClick={() => router.push(ROUTES.BRANDS)} sx={{ mb: 2 }}>
        Back to Brands
      </Button>

      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      )}
      {isError && <Alert severity="error">Could not load brand #{id}.</Alert>}
      {!isLoading && !brand && <Alert severity="warning">Brand #{id} was not found in the registry.</Alert>}

      {brand && (
        <Card>
          <CardContent sx={{ p: 3 }}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                <Box sx={{ p: 1.2, borderRadius: 2, backgroundColor: '#EFF6FF', color: 'primary.main' }}>
                  <Tag size={24} />
                </Box>
                <Box>
                  <Typography variant="h6" sx={{ fontWeight: 700 }}>
                    {brand.name}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    Slug: {brand.slug}
                  </Typography>
                </Box>
              </Box>
              <StatusBadge status={brand.is_active ? 'ACTIVE' : 'INACTIVE'} size="medium" />
            </Box>
            <Divider sx={{ my: 2 }} />
            <Grid container spacing={2}>
              <Grid item xs={12} sm={8}>
                <Typography variant="caption" color="text.secondary">
                  Description
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {brand.description || 'No description provided'}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={4}>
                <Typography variant="caption" color="text.secondary">
                  Mapped Products
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {brand.product_count ?? 0}
                </Typography>
              </Grid>
            </Grid>
          </CardContent>
        </Card>
      )}
    </Box>
  );
}
