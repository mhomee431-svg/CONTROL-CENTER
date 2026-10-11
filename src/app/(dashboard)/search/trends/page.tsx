'use client';

import React from 'react';
import { useQuery } from '@tanstack/react-query';
import {
  Box,
  Typography,
  Card,
  CardContent,
  Alert,
  CircularProgress,
  Grid,
  Chip,
  List,
  ListItem,
  ListItemText,
} from '@mui/material';
import { LineChart } from '@mui/x-charts/LineChart';
import { BarChart } from '@mui/x-charts/BarChart';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { SearchControlSummary } from '@/core/types/searchControl';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';
import { useDateRange } from '@/core/filters/DateRangeContext';
import { DateRangePicker } from '@/core/filters/DateRangePicker';

// ---------------------------------------------------------------------------
// Search Trends — the time-series demand signal.
// Charts: daily search volume with the zero-result overlay (both series are
//         real recorded counts from /admin/search/summary — no projection),
//         searches by location, and the top-terms bar.
// ---------------------------------------------------------------------------

export default function SearchTrendsPage() {
  const { params: dateParams } = useDateRange();

  const { data, isLoading, isError } = useQuery<SearchControlSummary>({
    queryKey: ['admin', 'search-control', 'summary', dateParams],
    queryFn: () =>
      apiClient<SearchControlSummary>(API_ENDPOINTS.SEARCH_CONTROL.SUMMARY, { params: dateParams }),
    retry: false,
  });

  const byDay = data?.volume?.searches_by_day || [];
  const zeroByDay = data?.volume?.zero_by_day || [];
  const byLocation = data?.volume?.searches_by_location || [];
  const topTerms = (data?.top_searches || []).slice(0, 10);

  // Align the zero series to the volume series dates (both come from the same
  // backend window, but guard the zip so a missing day renders as zero, which
  // is a real recorded zero for that day).
  const zeroCounts = byDay.map((d) => zeroByDay.find((z) => z.date === d.date)?.count ?? 0);


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
          Time-series demand signal across the discovery funnel — real recorded counts only.
        </Typography>
      </Box>

      {isError && (
        <Alert severity="warning" sx={{ mb: 2 }}>
          Search control endpoint is unavailable. No trend is shown rather than a fabricated one.
        </Alert>
      )}
      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 3 }}>
          <CircularProgress />
        </Box>
      )}

      <Card sx={{ mb: 3 }}>
        <CardContent sx={{ p: 3 }}>
          <Box sx={{ display: 'flex', gap: 1, alignItems: 'center', mb: 2 }}>
            <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>
              Daily Search Volume
            </Typography>
            <Chip size="small" label="All searches" color="primary" variant="outlined" />
            <Chip size="small" label="Zero-result" color="error" variant="outlined" />
          </Box>
          {byDay.length > 0 ? (
            <Box sx={{ width: '100%', overflowX: 'auto' }}>
              <LineChart
                height={300}
                xAxis={[{ scaleType: 'point', data: byDay.map((d) => d.date) }]}
                series={[
                  { data: byDay.map((d) => d.count), label: 'Searches', color: '#0F52BA' },
                  { data: zeroCounts, label: 'Zero-result', color: '#EF4444' },
                ]}
              />
            </Box>
          ) : (
            !isLoading && (
              <Typography variant="body2" color="text.secondary" sx={{ py: 5, textAlign: 'center' }}>
                No searches recorded in this window.
              </Typography>
            )
          )}
        </CardContent>
      </Card>

      <Grid container spacing={3}>
        <Grid item xs={12} md={6}>
          <Card sx={{ height: '100%' }}>
            <CardContent sx={{ p: 3 }}>
              <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 2 }}>
                Searches by Location
              </Typography>
              {byLocation.length > 0 ? (
                <Box sx={{ width: '100%', overflowX: 'auto' }}>
                  <BarChart
                    height={280}
                    xAxis={[{ scaleType: 'band', data: byLocation.map((l) => l.location) }]}
                    series={[{ data: byLocation.map((l) => l.count), label: 'Searches', color: '#8B5CF6' }]}
                  />
                </Box>
              ) : (
                <Typography variant="body2" color="text.secondary">
                  No location-tagged searches in this window.
                </Typography>
              )}
            </CardContent>
          </Card>
        </Grid>
        <Grid item xs={12} md={6}>
          <Card sx={{ height: '100%' }}>
            <CardContent sx={{ p: 3 }}>
              <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 1 }}>
                Top Terms
              </Typography>
              {topTerms.length === 0 ? (
                <Typography variant="body2" color="text.secondary">
                  No searches recorded in this window.
                </Typography>
              ) : (
                <List dense>
                  {topTerms.map((t) => (
                    <ListItem key={t.term} divider>
                      <ListItemText
                        primary={t.term}
                        secondary={`${t.zero_count} zero-result · avg ${t.avg_result_count ?? '—'} results`}
                      />
                      <Chip size="small" label={t.count.toLocaleString()} color="primary" variant="outlined" />
                    </ListItem>
                  ))}
                </List>
              )}
            </CardContent>
          </Card>
        </Grid>
      </Grid>
    </Box>
  );
}
