'use client';

import React from 'react';
import {
  Alert,
  Box,
  Card,
  CardContent,
  CircularProgress,
  Grid,
  List,
  ListItem,
  ListItemText,
  Typography,
} from '@mui/material';
import { BarChart } from '@mui/x-charts/BarChart';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';
import { useDateRange } from '@/core/filters/DateRangeContext';
import { DateRangePicker } from '@/core/filters/DateRangePicker';
import { AnalyticsChart } from '@/core/analytics/AnalyticsChart';
import { chartKindFor } from '@/core/analytics/chartPolicy';

/**
 * Presentation primitives shared by every analytics section.
 *
 * These keep each section route thin and guarantee the six surfaces present
 * numbers identically. Two contracts matter here:
 *
 *  1. A metric the backend does not collect is `null` and renders as an
 *     explicit "Not collected" state — never as a fabricated zero.
 *  2. A failed request renders "Unavailable" rather than zero, so an outage is
 *     never mistaken for a real finding of no activity.
 */

export interface AnalyticsKpi {
  label: string;
  /** `null` means "not collected"; the renderer shows an explicit state. */
  value: string | number | null;
  color: string;
  /** Optional sub-label, e.g. a period-over-period change. */
  hint?: string;
}

/** A single row in a breakdown list. */
export interface AnalyticsBreakdownItem {
  label: string;
  value: number | string;
}

export interface AnalyticsBreakdown {
  title: string;
  items: AnalyticsBreakdownItem[];
  /** Rendered under the title when there are no rows. */
  emptyText?: string;
}

export interface AnalyticsPageProps {
  title: string;
  description: string;
  kpis: AnalyticsKpi[];
  chartTitle: string;
  chartData: Array<{ label: string; value: number }>;
  /**
   * Policy key deciding which chart type this dataset earns, per the DATA
   * VISUALIZATION RULE. When null, no chart is rendered at all — a dataset
   * that does not earn one stays a number.
   */
  chartKey: string;
  breakdowns?: AnalyticsBreakdown[];
  /** True while the section's own query is in flight. */
  isLoading: boolean;
  /** True when the section's query failed. */
  isError: boolean;
  /** Optional extra alert (e.g. a partially-degraded section). */
  notice?: string;
}

function formatKpiValue(value: string | number | null): string {
  if (value === null) return 'Not collected';
  return typeof value === 'number' ? value.toLocaleString() : value;
}

export function AnalyticsPage({
  title,
  description,
  kpis,
  chartTitle,
  chartData,
  chartKey,
  breakdowns = [],
  isLoading,
  isError,
  notice,
}: AnalyticsPageProps) {
  const { label: rangeLabel } = useDateRange();
  // The dataset earns a chart only when policy grants one. A null chart
  // renders no chart at all — the numbers stay KPI cards.
  const chartKind = chartKindFor(chartKey);

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
        <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 0.5 }}>
          Reporting window: {rangeLabel}
        </Typography>
      </Box>

      <DateRangePicker />

      {isError && (
        <Alert severity="error" sx={{ mb: 2 }}>
          This analytics endpoint is unavailable — figures are withheld rather than reported as
          zero.
        </Alert>
      )}

      {notice && (
        <Alert severity="info" sx={{ mb: 2 }}>
          {notice}
        </Alert>
      )}

      <Grid container spacing={2.5} sx={{ mb: 3 }}>
        {kpis.map((kpi) => {
          const notCollected = kpi.value === null;
          return (
            <Grid item xs={12} sm={6} md={3} key={kpi.label}>
              <Card sx={{ borderLeft: `4px solid ${kpi.color}`, height: '100%' }}>
                <CardContent sx={{ p: 2.5 }}>
                  <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 600 }}>
                    {kpi.label}
                  </Typography>
                  <Typography
                    variant="h5"
                    sx={{
                      fontWeight: 700,
                      mt: 0.5,
                      fontSize: notCollected ? '1rem' : undefined,
                      color: notCollected ? 'text.secondary' : undefined,
                    }}
                  >
                    {isLoading ? '…' : isError ? 'Unavailable' : formatKpiValue(kpi.value)}
                  </Typography>
                  {kpi.hint && (
                    <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 0.5 }}>
                      {kpi.hint}
                    </Typography>
                  )}
                </CardContent>
              </Card>
            </Grid>
          );
        })}
      </Grid>

      <Card sx={{ mb: 3 }}>
        <CardContent sx={{ p: 3 }}>
          <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 2 }}>
            {chartTitle}
          </Typography>
          {isLoading ? (
            <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
              <CircularProgress />
            </Box>
          ) : isError ? (
            <Typography variant="body2" color="text.secondary" sx={{ py: 4, textAlign: 'center' }}>
              Trend unavailable.
            </Typography>
          ) : chartKind ? (
            <AnalyticsChart kind={chartKind} data={chartData} title={chartTitle} />
          ) : (
            // Policy grants no chart for this dataset — the numbers above stay
            // as KPI cards rather than becoming a chart for its own sake.
            <Typography variant="body2" color="text.secondary" sx={{ py: 4, textAlign: 'center' }}>
              No trend data available for this window.
            </Typography>
          )}
        </CardContent>
      </Card>

      {breakdowns.length > 0 && (
        <Grid container spacing={2.5}>
          {breakdowns.map((breakdown) => (
            <Grid item xs={12} md={6} key={breakdown.title}>
              <Card sx={{ height: '100%' }}>
                <CardContent sx={{ p: 3 }}>
                  <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 1 }}>
                    {breakdown.title}
                  </Typography>
                  {breakdown.items.length === 0 ? (
                    <Typography variant="body2" color="text.secondary" sx={{ py: 2 }}>
                      {breakdown.emptyText || 'No data for this window.'}
                    </Typography>
                  ) : (
                    <List dense>
                      {breakdown.items.map((item) => (
                        <ListItem
                          key={`${breakdown.title}-${item.label}`}
                          sx={{ borderBottom: '1px solid #F1F5F9' }}
                        >
                          <ListItemText
                            primary={item.label}
                            primaryTypographyProps={{ fontSize: '0.8125rem' }}
                          />
                          <Typography variant="body2" sx={{ fontWeight: 700 }}>
                            {typeof item.value === 'number' ? item.value.toLocaleString() : item.value}
                          </Typography>
                        </ListItem>
                      ))}
                    </List>
                  )}
                </CardContent>
              </Card>
            </Grid>
          ))}
        </Grid>
      )}
    </Box>
  );
}

export default AnalyticsPage;
