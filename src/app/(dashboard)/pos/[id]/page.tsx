'use client';

import React, { use } from 'react';
import { useRouter } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { Box, Card, CardContent, Button, Typography, Alert, CircularProgress, Divider, Grid } from '@mui/material';
import { ArrowLeft, Plug } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';

interface PosIntegration {
  id: number;
  shop_id?: number | null;
  shop_name?: string | null;
  name?: string;
  category?: string;
  city?: string;
  state?: string;
  status?: string;
  verification_status?: string;
  provider?: string;
  last_sync?: string;
  product_count?: number;
}

export default function PosDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const router = useRouter();

  // Integration detail from the dedicated POS registry. This previously read
  // /admin/shops, which has no provider/status/last_sync fields, so every value
  // on this page rendered blank for every integration.
  const { data: integration, isLoading, isError, refetch } = useQuery<PosIntegration | null>({
    queryKey: ['admin', 'pos', 'detail', id],
    queryFn: async () => {
      try {
        return await apiClient<PosIntegration>(
          API_ENDPOINTS.INGESTION.POS_INTEGRATION_DETAIL(id)
        );
      } catch {
        const res = await apiClient<{ items: PosIntegration[] }>(
          API_ENDPOINTS.INGESTION.POS_INTEGRATIONS,
          { params: { limit: 250 } }
        );
        return res.items?.find((s) => String(s.id) === String(id)) ?? null;
      }
    },
    retry: false,
  });

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'POS', href: ROUTES.POS },
          { label: `Integration #${id}` },
        ]}
      />
      <Button startIcon={<ArrowLeft size={16} />} onClick={() => router.push(ROUTES.POS)} sx={{ mb: 2 }}>
        Back to POS Integrations
      </Button>

      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      )}
      {isError && <Alert severity="error">Could not load POS integration #{id}.</Alert>}
      {!isLoading && !isError && !integration && (
        <Alert severity="warning">POS integration #{id} was not found in the connected-shop registry.</Alert>
      )}

      {integration && (
        <Card>
          <CardContent sx={{ p: 3 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2 }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                <Box sx={{ p: 1.2, borderRadius: 2, backgroundColor: '#EFF6FF', color: 'primary.main' }}>
                  <Plug size={24} />
                </Box>
                <Box>
                  <Typography variant="h6" sx={{ fontWeight: 700 }}>
                    {integration.name || `Integration #${integration.id}`}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    Integration #{integration.id}
                  </Typography>
                </Box>
              </Box>
              <StatusBadge status={integration.status || 'PENDING'} size="medium" />
            </Box>

            <Divider sx={{ my: 2 }} />

            <Grid container spacing={2}>
              <Grid item xs={12} sm={6}>
                <Typography variant="caption" color="text.secondary">
                  POS Provider
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {integration.provider || 'Not reported by backend'}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={6}>
                <Typography variant="caption" color="text.secondary">
                  Last Sync
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {integration.last_sync ? new Date(integration.last_sync).toLocaleString() : 'N/A'}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={6}>
                <Typography variant="caption" color="text.secondary">
                  Merchant Category
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {integration.category || 'Unspecified'}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={6}>
                <Typography variant="caption" color="text.secondary">
                  Location
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {[integration.city, integration.state].filter(Boolean).join(', ') || 'Not provided'}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={6}>
                <Typography variant="caption" color="text.secondary">
                  Verification
                </Typography>
                <Box sx={{ mt: 0.5 }}>
                  <StatusBadge status={integration.verification_status || 'UNVERIFIED'} />
                </Box>
              </Grid>
              <Grid item xs={12} sm={6}>
                <Typography variant="caption" color="text.secondary">
                  Catalogued Products
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {(integration.product_count ?? 0).toLocaleString()}
                </Typography>
              </Grid>
            </Grid>

            <Box sx={{ mt: 3 }}>
              <Button
                variant="outlined"
                onClick={() => router.push(ROUTES.BUSINESS_DETAIL(integration.id))}
              >
                Open Full Business Profile →
              </Button>
            </Box>

            <Alert severity="info" sx={{ mt: 2.5 }}>
              Detailed POS sync logs and SKU mapping are provided by the backend integration endpoint. The
              connection above is served by the authoritative shop registry.
            </Alert>
          </CardContent>
        </Card>
      )}
    </Box>
  );
}
