'use client';

import React from 'react';
import { useQuery } from '@tanstack/react-query';
import { Box, Typography, Grid, Card, CardContent, Alert, CircularProgress, List, ListItem, ListItemText } from '@mui/material';
import { BarChart } from '@mui/x-charts/BarChart';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AnalyticsSummary } from '@/core/types/analytics';
import { DashboardMetrics } from '@/core/types/admin';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';

export interface AnalyticsKpi {
  label: string;
  value: string | number;
  color: string;
}

interface Props {
  title: string;
  description: string;
  /**
   * KPI definitions. When `resolveKpis` is provided it receives the loaded
   * summary/metrics and must return the final values — this lets each section
   * bind real backend figures instead of static placeholders.
   */
  kpis: AnalyticsKpi[];
  resolveKpis?: (data: { summary: AnalyticsSummary | undefined; metrics: DashboardMetrics | undefined; isLoading: boolean }) => AnalyticsKpi[];
  chartTitle?: string;
  chartData?: Array<{ label: string; value: number }>;
  /** Optional per-section extra list, sourced from the analytics summary. */
  secondaryListSource?: 'top_categories_searched' | 'top_search_terms' | 'zero_result_queries' | 'searches_by_location';
  secondaryListTitle?: string;
}

/**
 * Shared analytics section renderer. Keeps the analytics routes thin and
 * guarantees consistent presentation + drill-down breadcrumbs.
 *
 * Data sources: the search analytics summary (`/analytics/summary`) and the
 * platform dashboard metrics (`/dashboard/metrics`). Sections bind live values
 * via `resolveKpis`; anything the backend does not report stays as "—".
 */
export function AnalyticsSection({ title, description, kpis, resolveKpis, chartTitle, chartData, secondaryListSource, secondaryListTitle }: Props) {
  const summaryQuery = useQuery<AnalyticsSummary>({
    queryKey: ['admin', 'analytics', 'summary'],
    queryFn: () => apiClient<AnalyticsSummary>(API_ENDPOINTS.DASHBOARD.ANALYTICS_SUMMARY),
    retry: false,
  });

  const metricsQuery = useQuery<DashboardMetrics>({
    queryKey: ['admin', 'dashboard', 'metrics'],
    queryFn: () => apiClient<DashboardMetrics>(API_ENDPOINTS.DASHBOARD.METRICS),
    retry: false,
  });

  const summary = summaryQuery.data;
  const metrics = metricsQuery.data;
  const isLoading = summaryQuery.isLoading || metricsQuery.isLoading;
  const isError = summaryQuery.isError && metricsQuery.isError;

  const resolvedKpis = resolveKpis
    ? resolveKpis({ summary, metrics, isLoading })
    : kpis;

  const series = chartData ?? summary?.searches_by_day?.map((d) => ({ label: d.date, value: d.count })) ?? [];

  // Resolve the requested secondary list from whichever summary array carries it.
  let secondaryItems: Array<{ label: string; value?: number }> = [];
  if (secondaryListSource === 'top_search_terms') secondaryItems = summary?.top_search_terms?.map((t) => ({ label: t.term, value: t.count })) ?? [];
  else if (secondaryListSource === 'top_categories_searched') secondaryItems = summary?.top_categories_searched?.map((c) => ({ label: c.category, value: c.count })) ?? [];
  else if (secondaryListSource === 'zero_result_queries') secondaryItems = summary?.zero_result_queries?.map((q) => ({ label: q.location ? `${q.query} — ${q.location}` : q.query, value: q.count })) ?? [];
  else if (secondaryListSource === 'searches_by_location') secondaryItems = summary?.searches_by_location?.map((l) => ({ label: l.location, value: l.count })) ?? [];

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Analytics', href: ROUTES.ANALYTICS },
          { label: title },
        ]}
      />

      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          {title}
        </Typography>
        <Typography variant="body2" color="text.secondary">
          {description}
        </Typography>
      </Box>

      {isError && (
        <Alert severity="warning" sx={{ mb: 2 }}>
          Analytics endpoints are unavailable. Showing configured section KPIs.
        </Alert>
      )}

      <Grid container spacing={2.5} sx={{ mb: 3 }}>
        {resolvedKpis.map((kpi) => (
          <Grid item xs={12} sm={6} md={3} key={kpi.label}>
            <Card sx={{ borderLeft: `4px solid ${kpi.color}` }}>
              <CardContent sx={{ p: 2.5 }}>
                <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 600 }}>
                  {kpi.label}
                </Typography>
                <Typography variant="h5" sx={{ fontWeight: 700, mt: 0.5 }}>
                  {isLoading ? '...' : kpi.value}
                </Typography>
              </CardContent>
            </Card>
          </Grid>
        ))}
      </Grid>

      <Card sx={{ mb: 3 }}>
        <CardContent sx={{ p: 3 }}>
          <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 2 }}>
            {chartTitle || 'Search Volume Trend'}
          </Typography>
          {isLoading ? (
            <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
              <CircularProgress />
            </Box>
          ) : series.length > 0 ? (
            <Box sx={{ width: '100%', overflowX: 'auto' }}>
              <BarChart
                height={280}
                xAxis={[{ scaleType: 'band', data: series.map((s) => s.label) }]}
                series={[{ data: series.map((s) => s.value), label: 'Count', color: '#0F52BA' }]}
                slotProps={{ legend: { hidden: true } }}
              />
            </Box>
          ) : (
            <Typography variant="body2" color="text.secondary" sx={{ py: 4, textAlign: 'center' }}>
              No trend data available yet.
            </Typography>
          )}
        </CardContent>
      </Card>

      {summaryQuery.data?.top_search_terms && summaryQuery.data.top_search_terms.length > 0 && (
        <Card>
          <CardContent sx={{ p: 3 }}>
            <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 1 }}>
              Top Search Terms
            </Typography>
            <List dense>
              {summaryQuery.data.top_search_terms.slice(0, 8).map((term) => (
                <ListItem key={term.term} sx={{ borderBottom: '1px solid #F1F5F9' }}>
                  <ListItemText primary={term.term} primaryTypographyProps={{ fontSize: '0.8125rem' }} />
                  <Typography variant="body2" sx={{ fontWeight: 700 }}>
                    {term.count.toLocaleString()}
                  </Typography>
                </ListItem>
              ))}
            </List>
          </CardContent>
        </Card>
      )}

      {secondaryListSource && secondaryItems.length > 0 && (
        <Card>
          <CardContent sx={{ p: 3 }}>
            <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 1 }}>
              {secondaryListTitle || 'Breakdown'}
            </Typography>
            <List dense>
              {secondaryItems.slice(0, 8).map((item) => (
                <ListItem key={item.label} sx={{ borderBottom: '1px solid #F1F5F9' }}>
                  <ListItemText primary={item.label} primaryTypographyProps={{ fontSize: '0.8125rem' }} />
                  {item.value !== undefined && (
                    <Typography variant="body2" sx={{ fontWeight: 700 }}>
                      {item.value.toLocaleString()}
                    </Typography>
                  )}
                </ListItem>
              ))}
            </List>
          </CardContent>
        </Card>
      )}
    </Box>
  );
}
