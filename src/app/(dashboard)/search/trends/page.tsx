'use client';

import React from 'react';
import { useQuery } from '@tanstack/react-query';
import { Box, Typography, Card, CardContent, Alert, CircularProgress } from '@mui/material';
import { LineChart } from '@mui/x-charts/LineChart';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AnalyticsSummary } from '@/core/types/analytics';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';
import { useDateRange } from '@/core/filters/DateRangeContext';
import { DateRangePicker } from '@/core/filters/DateRangePicker';

export default function SearchTrendsPage() {
  const { params: dateParams } = useDateRange();

  const { data, isLoading, isError } = useQuery<AnalyticsSummary>({
    queryKey: ['admin', 'analytics', 'summary', dateParams],
    queryFn: () =>
      apiClient<AnalyticsSummary>(API_ENDPOINTS.DASHBOARD.ANALYTICS_SUMMARY, {
        params: dateParams,
      }),
    retry: false,
  });

  const byDay = data?.searches_by_day || [];

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Search', href: ROUTES.SEARCH },
          { label: 'Trends' },
        ]}
      />
      <DateRangePicker />

      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Search Trends
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Time-series demand signal across the discovery funnel.
        </Typography>
      </Box>

      {isError && (
        <Alert severity="warning" sx={{ mb: 2 }}>
          Analytics summary endpoint is unavailable.
        </Alert>
      )}

      <Card>
        <CardContent sx={{ p: 3 }}>
          <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 2 }}>
            Daily Search Volume
          </Typography>
          {isLoading ? (
            <Box sx={{ display: 'flex', justifyContent: 'center', py: 5 }}>
              <CircularProgress />
            </Box>
          ) : byDay.length > 0 ? (
            <Box sx={{ width: '100%', overflowX: 'auto' }}>
              <LineChart
                height={300}
                xAxis={[{ scaleType: 'point', data: byDay.map((d) => d.date) }]}
                series={[{ data: byDay.map((d) => d.count), label: 'Searches', color: '#0F52BA' }]}
              />
            </Box>
          ) : (
            <Typography variant="body2" color="text.secondary" sx={{ py: 5, textAlign: 'center' }}>
              No trend data available yet.
            </Typography>
          )}
        </CardContent>
      </Card>
    </Box>
  );
}
