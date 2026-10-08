'use client';

import React from 'react';
import { Box, Typography } from '@mui/material';
import { BarChart } from '@mui/x-charts/BarChart';
import { LineChart } from '@mui/x-charts/LineChart';
import { PieChart } from '@mui/x-charts/PieChart';
import { ChartKind } from './chartPolicy';

/**
 * The single renderer for every analytics chart.
 *
 * Colour, height and empty-state behaviour are decided here once, so six
 * sections cannot drift into six different chart dialects. `kind` comes from
 * `chartPolicy` — a dataset earns its chart type by policy, not by preference.
 */

const PRIMARY = '#0F52BA';

const PALETTE = ['#0F52BA', '#10B981', '#A855F7', '#F59E0B', '#EF4444', '#14B8A6', '#EC4899', '#6366F1'];

export interface AnalyticsChartProps {
  kind: ChartKind;
  data: Array<{ label: string; value: number }>;
  /** Aria label and fallback title. */
  title: string;
  height?: number;
}

export function AnalyticsChart({ kind, data, title, height = 280 }: AnalyticsChartProps) {
  if (data.length === 0) {
    return (
      <Typography variant="body2" color="text.secondary" sx={{ py: 4, textAlign: 'center' }}>
        No data available for this chart.
      </Typography>
    );
  }

  const labels = data.map((d) => d.label);
  const values = data.map((d) => d.value);

  return (
    <Box sx={{ width: '100%', overflowX: 'auto' }} role="img" aria-label={title}>
      {kind === 'bar' && (
        <BarChart
          height={height}
          xAxis={[{ scaleType: 'band', data: labels }]}
          series={[{ data: values, label: title, color: PRIMARY }]}
          slotProps={{ legend: { hidden: true } }}
        />
      )}
      {(kind === 'line' || kind === 'area') && (
        <LineChart
          height={height}
          xAxis={[{ scaleType: 'point', data: labels }]}
          series={[{ data: values, label: title, color: PRIMARY, area: kind === 'area' }]}
          slotProps={{ legend: { hidden: true } }}
        />
      )}
      {kind === 'donut' && (
        <PieChart
          height={height}
          series={[
            {
              data: data.map((d, i) => ({ id: d.label, value: d.value, label: d.label, color: PALETTE[i % PALETTE.length] })),
              innerRadius: height * 0.25,
              outerRadius: height * 0.4,
              arcLabel: (p) => `${p.value}`,
            },
          ]}
        />
      )}
    </Box>
  );
}

export default AnalyticsChart;
