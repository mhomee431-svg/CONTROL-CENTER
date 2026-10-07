'use client';

import React from 'react';
import { AnalyticsSection, AnalyticsKpi } from '@/core/components/AnalyticsSection';
import { DashboardMetrics } from '@/core/types/admin';

export default function AnalyticsGeographyPage() {
  const resolveKpis = ({
    summary,
    metrics,
    isLoading,
  }: {
    summary?: { zero_result_queries?: Array<{ query: string; count: number; location?: string }> };
    metrics?: DashboardMetrics;
    isLoading: boolean;
  }): AnalyticsKpi[] => {
    const zeroResultLocations = (summary?.zero_result_queries || []).filter((q) => q.location);
    return [
      {
        label: 'TOTAL SHOPS ON PLATFORM',
        value: isLoading ? '...' : (metrics?.total_shops ?? '—'),
        color: '#EC4899',
      },
      {
        label: 'ACTIVE REGIONS SERVED',
        value: isLoading ? '...' : (metrics?.active_shops ?? '—'),
        color: '#0F52BA',
      },
      {
        label: 'LOCATION-GAPPED QUERIES',
        value: isLoading ? '...' : zeroResultLocations.length,
        color: '#EF4444',
      },
      {
        label: 'POPULAR CATEGORY HOTSPOTS',
        value: isLoading
          ? '...'
          : metrics?.popular_categories?.length
          ? metrics.popular_categories.length
          : '—',
        color: '#F59E0B',
      },
    ];
  };

  return (
    <AnalyticsSection
      title="Geography Analytics"
      description="Regional demand, merchant coverage gaps, and hyperlocal density."
      kpis={[]}
      resolveKpis={resolveKpis}
      chartTitle="Regional Activity Distribution"
      secondaryListSource="zero_result_queries"
      secondaryListTitle="Location-Gapped Queries (Coverage Gaps)"
    />
  );
}
