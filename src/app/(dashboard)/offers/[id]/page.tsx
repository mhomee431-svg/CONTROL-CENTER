'use client';

import React from 'react';
import { useRouter } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { Box, Card, CardContent, Button, Typography, Divider, Alert, CircularProgress, Grid } from '@mui/material';
import { ArrowLeft, DollarSign } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { OfferItem } from '@/core/types/admin';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';

export default function OfferDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = React.use(params);
  const router = useRouter();

  const { data, isLoading, isError } = useQuery<{ items: OfferItem[] }>({
    queryKey: ['admin', 'offers'],
    queryFn: () =>
      apiClient<{ items: OfferItem[] }>(API_ENDPOINTS.OFFERS.LIST, { params: { limit: 250 } }),
  });

  const offer = data?.items?.find((o) => String(o.id) === String(id));

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Offers', href: ROUTES.OFFERS },
          { label: offer?.title || `Offer #${id}` },
        ]}
      />
      <Button startIcon={<ArrowLeft size={16} />} onClick={() => router.push(ROUTES.OFFERS)} sx={{ mb: 2 }}>
        Back to Offers
      </Button>

      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      )}
      {isError && <Alert severity="error">Could not load offer #{id}.</Alert>}
      {!isLoading && !offer && <Alert severity="warning">Offer #{id} was not found.</Alert>}

      {offer && (
        <Card>
          <CardContent sx={{ p: 3 }}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                <Box sx={{ p: 1.2, borderRadius: 2, backgroundColor: '#ECFDF5', color: '#10B981' }}>
                  <DollarSign size={24} />
                </Box>
                <Box>
                  <Typography variant="h6" sx={{ fontWeight: 700 }}>
                    {offer.title}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    Offer ID: #{offer.id} · Shop: {offer.shop_name || `#${offer.shop_id}`}
                  </Typography>
                </Box>
              </Box>
              <StatusBadge status={offer.status} size="medium" />
            </Box>
            <Divider sx={{ my: 2 }} />
            <Grid container spacing={2}>
              <Grid item xs={12} sm={4}>
                <Typography variant="caption" color="text.secondary">
                  Discount
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {offer.discount_value}
                  {offer.discount_type === 'PERCENTAGE' ? '%' : ' OFF'}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={4}>
                <Typography variant="caption" color="text.secondary">
                  Valid From
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {offer.valid_from ? new Date(offer.valid_from).toLocaleDateString() : 'N/A'}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={4}>
                <Typography variant="caption" color="text.secondary">
                  Valid Until
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {offer.valid_until ? new Date(offer.valid_until).toLocaleDateString() : 'N/A'}
                </Typography>
              </Grid>
            </Grid>
          </CardContent>
        </Card>
      )}
    </Box>
  );
}
