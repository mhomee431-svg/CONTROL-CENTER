'use client';

import React from 'react';
import { useRouter } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { Box, Card, CardContent, Button, Typography, Divider, Alert, CircularProgress, Grid } from '@mui/material';
import { ArrowLeft, ShieldCheck } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { ShopItem } from '@/core/types/admin';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';

export default function VerificationDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = React.use(params);
  const router = useRouter();

  const { data: shop, isLoading, isError } = useQuery<ShopItem>({
    queryKey: ['admin', 'shops', id],
    queryFn: () => apiClient<ShopItem>(API_ENDPOINTS.SHOPS.DETAIL(id)),
  });

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Verification', href: ROUTES.VERIFICATION },
          { label: shop?.name || `Case #${id}` },
        ]}
      />
      <Button startIcon={<ArrowLeft size={16} />} onClick={() => router.push(ROUTES.VERIFICATION)} sx={{ mb: 2 }}>
        Back to Verification Queue
      </Button>

      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      )}
      {isError && <Alert severity="error">Could not load verification case #{id}.</Alert>}

      {shop && (
        <Card>
          <CardContent sx={{ p: 3 }}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                <Box sx={{ p: 1.2, borderRadius: 2, backgroundColor: '#FFFBEB', color: '#F59E0B' }}>
                  <ShieldCheck size={24} />
                </Box>
                <Box>
                  <Typography variant="h6" sx={{ fontWeight: 700 }}>
                    {shop.name}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    Shop ID: #{shop.id} · Owner ID: #{shop.owner_id}
                  </Typography>
                </Box>
              </Box>
              <Box sx={{ display: 'flex', gap: 1 }}>
                <StatusBadge status={shop.status} size="medium" />
                <StatusBadge status={shop.verification_status} size="medium" />
              </Box>
            </Box>
            <Divider sx={{ my: 2 }} />
            <Grid container spacing={2}>
              <Grid item xs={12} sm={4}>
                <Typography variant="caption" color="text.secondary">
                  Category
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {shop.category}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={4}>
                <Typography variant="caption" color="text.secondary">
                  Location
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {shop.city}, {shop.state}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={4}>
                <Typography variant="caption" color="text.secondary">
                  Submitted
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {shop.created_at ? new Date(shop.created_at).toLocaleString() : 'N/A'}
                </Typography>
              </Grid>
            </Grid>
            <Box sx={{ mt: 3 }}>
              <Button
                variant="outlined"
                onClick={() => router.push(ROUTES.BUSINESS_DETAIL(shop.id))}
              >
                Open Full Business Profile →
              </Button>
            </Box>
          </CardContent>
        </Card>
      )}
    </Box>
  );
}
