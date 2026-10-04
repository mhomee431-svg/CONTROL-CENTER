'use client';

import React from 'react';
import { useQuery } from '@tanstack/react-query';
import { Box, Typography, Card, CardContent, Alert, CircularProgress, Chip } from '@mui/material';
import { MapPin } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { ShopItem, ShopStatus, VerificationStatus } from '@/core/types/admin';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';

interface LocationRow extends ShopItem {
  status: ShopStatus;
  verification_status: VerificationStatus;
}

/**
 * Map view: renders geographic coverage as a positioned density board.
 * Uses a real data query; visual markers use a CSS grid so no external map
 * provider keys are required in the control center.
 */
export default function LocationsMapPage() {
  const { data, isLoading, isError } = useQuery<{ items: LocationRow[] }>({
    queryKey: ['admin', 'locations', 'map'],
    queryFn: () => apiClient<{ items: LocationRow[] }>(API_ENDPOINTS.SHOPS.LIST, { params: { limit: 250 } }),
  });

  const grouped = (data?.items || []).reduce<Record<string, number>>((acc, shop) => {
    const key = shop.city || 'Unmapped';
    acc[key] = (acc[key] || 0) + 1;
    return acc;
  }, {});

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Locations', href: ROUTES.LOCATIONS },
          { label: 'Map' },
        ]}
      />
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Geographic Coverage Map
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Hyperlocal density board — shops aggregated by city/region.
        </Typography>
      </Box>

      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      )}
      {isError && <Alert severity="error">Could not load location coverage.</Alert>}

      {!isLoading && (
        <Card>
          <CardContent sx={{ p: 3 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 2 }}>
              <MapPin size={18} color="#0F52BA" />
              <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>
                Shops by City ({Object.keys(grouped).length} regions)
              </Typography>
            </Box>
            <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 1.5 }}>
              {Object.entries(grouped).map(([city, count]) => (
                <Chip
                  key={city}
                  label={`${city}: ${count} shops`}
                  color={count >= 5 ? 'primary' : count >= 2 ? 'success' : 'default'}
                  variant={count >= 2 ? 'filled' : 'outlined'}
                />
              ))}
              {Object.keys(grouped).length === 0 && (
                <Typography variant="body2" color="text.secondary">
                  No shop locations available yet.
                </Typography>
              )}
            </Box>
          </CardContent>
        </Card>
      )}
    </Box>
  );
}
