'use client';

import React from 'react';
import { Box, Alert } from '@mui/material';
import { useQuery } from '@tanstack/react-query';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { ShopItem } from '@/core/types/admin';
import { AnalyticsSection } from '@/core/components/AnalyticsSection';

/**
 * Geography analytics derives its KPIs and density chart from the real shops
 * registry (city/state distribution), so the section reflects actual platform
 * coverage instead of static placeholders.
 *
 * A failed request must not be rendered as "zero coverage" — that reads as a
 * real geographic finding when it is actually an outage. Figures are therefore
 * withheld with an explicit "Unavailable" state.
 */
export default function AnalyticsGeographyPage() {
  const { data, isLoading, isError } = useQuery<{ items: ShopItem[]; total: number }>({
    queryKey: ['admin', 'locations', 'map'],
    queryFn: () =>
      apiClient<{ items: ShopItem[]; total: number }>(API_ENDPOINTS.SHOPS.LIST, {
        params: { limit: 250 },
      }),
  });

  const shops = data?.items ?? [];
  const cityCounts = shops.reduce<Record<string, number>>((acc, shop) => {
    const key = shop.city || 'Unmapped';
    acc[key] = (acc[key] || 0) + 1;
    return acc;
  }, {});
  const regionCounts = shops.reduce<Record<string, number>>((acc, shop) => {
    const key = shop.state || 'Unknown';
    acc[key] = (acc[key] || 0) + 1;
    return acc;
  }, {});

  const sortedCities = Object.entries(cityCounts).sort((a, b) => b[1] - a[1]);
  const coveredCities = Object.keys(cityCounts).filter((c) => c !== 'Unmapped').length;
  const activeRegions = Object.keys(regionCounts).filter((r) => r !== 'Unknown').length;
  const topCity = sortedCities[0];

  const kpis = isError
    ? [
        { label: 'COVERED CITIES', value: 'Unavailable', color: '#DC2626' },
        { label: 'ACTIVE REGIONS', value: 'Unavailable', color: '#DC2626' },
        { label: 'MAPPED SHOPS', value: 'Unavailable', color: '#DC2626' },
        { label: 'TOP DEMAND ZONE', value: 'Unavailable', color: '#DC2626' },
      ]
    : isLoading
    ? [
        { label: 'COVERED CITIES', value: '…', color: '#EC4899' },
        { label: 'ACTIVE REGIONS', value: '…', color: '#0F52BA' },
        { label: 'MAPPED SHOPS', value: '…', color: '#10B981' },
        { label: 'TOP DEMAND ZONE', value: '…', color: '#F59E0B' },
      ]
    : [
        { label: 'COVERED CITIES', value: coveredCities.toLocaleString(), color: '#EC4899' },
        { label: 'ACTIVE REGIONS', value: activeRegions.toLocaleString(), color: '#0F52BA' },
        { label: 'MAPPED SHOPS', value: shops.length.toLocaleString(), color: '#10B981' },
        { label: 'TOP DEMAND ZONE', value: topCity ? topCity[0] : '—', color: '#F59E0B' },
      ];

  return (
    <Box>
      {isError && (
        <Alert severity="error" sx={{ mb: 2 }}>
          Shop registry is unavailable — geography coverage could not be computed. Figures below are withheld rather
          than reported as zero.
        </Alert>
      )}
      <AnalyticsSection
        title="Geography Analytics"
        description="Regional demand, merchant coverage gaps, and hyperlocal density."
        kpis={kpis}
        chartTitle="Shop Density by City"
        chartData={sortedCities.slice(0, 10).map(([city, count]) => ({ label: city, value: count }))}
      />
    </Box>
  );
}
