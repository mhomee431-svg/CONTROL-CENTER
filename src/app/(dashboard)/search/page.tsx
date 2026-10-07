'use client';

import React from 'react';
import { useRouter } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { Box, Typography, Grid, Card, CardContent, Button, Alert, CircularProgress } from '@mui/material';
import { Search, AlertCircle, TrendingUp, BarChart2 } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AnalyticsSummary } from '@/core/types/analytics';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';
import { useDateRange } from '@/core/filters/DateRangeContext';
import { DateRangePicker } from '@/core/filters/DateRangePicker';

/** Single KPI tile backed by the real analytics summary payload. */
function SearchKpi({
  label,
  value,
  icon,
}: {
  label: string;
  value: string;
  icon: React.ReactElement;
}) {
  return (
    <Grid item xs={12} sm={6} md={3}>
      <Card>
        <CardContent sx={{ p: 2.5 }}>
          <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <Box>
              <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 600 }}>
                {label}
              </Typography>
              <Typography variant="h5" sx={{ fontWeight: 800, mt: 0.5 }}>
                {value}
              </Typography>
            </Box>
            {icon}
          </Box>
        </CardContent>
      </Card>
    </Grid>
  );
}

export default function SearchAnalyticsPage() {
  const router = useRouter();

  // Real discovery-funnel metrics from the backend analytics summary.
  const { params: dateParams } = useDateRange();

  const { data: summary, isLoading, isError } = useQuery<AnalyticsSummary>({
    queryKey: ['admin', 'analytics', 'summary', dateParams],
    queryFn: () =>
      apiClient<AnalyticsSummary>(API_ENDPOINTS.DASHBOARD.ANALYTICS_SUMMARY, {
        params: dateParams,
      }),
    retry: false,
  });

  const zeroResultTotal = (summary?.zero_result_queries ?? []).reduce(
    (sum, q) => sum + (q.count || 0),
    0
  );

  const fmt = (v: number | undefined, suffix = '') =>
    !isLoading && summary ? (v != null ? `${v.toLocaleString()}${suffix}` : '—') : '…';

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Search' },
        ]}
      />

      {/* Centralized reporting-window control, shared with the dashboard. */}
      <DateRangePicker />

      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Search & Discovery Control Center
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Section 41 & 43: Local search funnel, product matching accuracy, latency, and discovery efficiency.
        </Typography>
      </Box>

      {isError && (
        <Alert severity="warning" sx={{ mb: 2 }}>
          Analytics summary endpoint is unavailable. Funnel KPIs cannot be verified right now.
        </Alert>
      )}

      <Grid container spacing={2.5} sx={{ mb: 4 }}>
        <SearchKpi
          label="SEARCH SUCCESS RATE"
          value={
            !isLoading && summary
              ? summary.search_success_rate != null
                ? `${summary.search_success_rate}%`
                : '—'
              : '…'
          }
          icon={<TrendingUp size={22} color="#10B981" />}
        />
        <SearchKpi
          label="TOTAL SEARCHES"
          value={fmt(summary?.total_searches)}
          icon={<BarChart2 size={22} color="#0F52BA" />}
        />
        <SearchKpi
          label="ZERO-RESULT QUERIES"
          value={fmt(zeroResultTotal)}
          icon={<AlertCircle size={22} color="#EF4444" />}
        />
        <SearchKpi
          label="UNIQUE SEARCHERS"
          value={fmt(summary?.unique_searchers)}
          icon={<Search size={22} color="#8B5CF6" />}
        />
      </Grid>

      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 3 }}>
          <CircularProgress />
        </Box>
      )}

      {/* Funnel Card */}
      <Card sx={{ p: 3 }}>
        <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 1 }}>
          Hyperlocal Offline Discovery Funnel (Section 43)
        </Typography>
        <Typography variant="body2" color="text.secondary" sx={{ mb: 3 }}>
          Customer Search → Products Found → Product Opened → Physical Store Directions Clicked.
          {summary ? ` ${summary.successful_searches.toLocaleString()} searches returned results this period.` : ''}
        </Typography>

        <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, flexWrap: 'wrap' }}>
          <Button
            variant="contained"
            color="primary"
            onClick={() => router.push(ROUTES.SEARCH_ZERO_RESULTS)}
          >
            Investigate Zero-Result Searches →
          </Button>
          <Button variant="outlined" onClick={() => router.push(ROUTES.SEARCH_QUALITY)}>
            Review Search Quality →
          </Button>
          <Button variant="outlined" onClick={() => router.push(ROUTES.SEARCH_TRENDS)}>
            Open Search Trends →
          </Button>
        </Box>
      </Card>
    </Box>
  );
}
