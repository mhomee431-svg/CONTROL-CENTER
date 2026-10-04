'use client';

import React from 'react';
import { useQuery } from '@tanstack/react-query';
import { Box, Typography, Grid, Card, CardContent, Alert, CircularProgress, List, ListItem, ListItemText } from '@mui/material';
import { BarChart } from '@mui/x-charts/BarChart';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AnalyticsSummary } from '@/core/types/analytics';
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
  kpis: AnalyticsKpi[];
  chartTitle?: string;
  chartData?: Array<{ label: string; value: number }>;
}

/**
 * Shared analytics section renderer. Keeps the six analytics routes thin and
 * guarantees consistent presentation + drill-down breadcrumbs.
 */
export function AnalyticsSection({ title, description, kpis, chartTitle, chartData }: Props) {
  const { data: summary, isLoading, isError } = useQuery<AnalyticsSummary>({
    queryKey: ['admin', 'analytics', 'summary'],
    queryFn: () => apiClient<AnalyticsSummary>(API_ENDPOINTS.DASHBOARD.ANALYTICS_SUMMARY),
    retry: false,
  });

  const series = chartData ?? summary?.searches_by_day?.map((d) => ({ label: d.date, value: d.count })) ?? [];

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
          Analytics summary endpoint is unavailable. Showing configured section KPIs.
        </Alert>
      )}

      <Grid container spacing={2.5} sx={{ mb: 3 }}>
        {kpis.map((kpi) => (
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

      {summary?.top_search_terms && summary.top_search_terms.length > 0 && (
        <Card>
          <CardContent sx={{ p: 3 }}>
            <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 1 }}>
              Top Search Terms
            </Typography>
            <List dense>
              {summary.top_search_terms.slice(0, 8).map((term) => (
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
    </Box>
  );
}
