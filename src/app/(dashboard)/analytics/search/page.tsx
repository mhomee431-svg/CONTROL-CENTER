'use client';

import React from 'react';
import { AnalyticsSection, AnalyticsKpi } from '@/core/components/AnalyticsSection';
import { AnalyticsSummary } from '@/core/types/analytics';

export default function AnalyticsSearchPage() {
  const resolveKpis = ({ summary, isLoading }: { summary?: AnalyticsSummary; isLoading: boolean }): AnalyticsKpi[] => [
    {
      label: 'TOTAL SEARCHES',
      value: isLoading ? '...' : (summary?.total_searches?.toLocaleString() ?? '—'),
      color: '#0F52BA',
    },
    {
      label: 'SUCCESS RATE',
      value: isLoading ? '...' : summary?.search_success_rate !== undefined ? `${summary.search_success_rate}%` : '—',
      color: '#10B981',
    },
    {
      label: 'UNIQUE SEARCHERS',
      value: isLoading ? '...' : (summary?.unique_searchers?.toLocaleString() ?? '—'),
      color: '#A855F7',
    },
    {
      label: 'ZERO-RESULT QUERIES',
      value: isLoading ? '...' : (summary?.zero_result_queries?.length ?? '—'),
      color: '#EF4444',
    },
  ];

  return (
    <AnalyticsSection
      title="Search Analytics"
      description="Discovery funnel performance, match quality, and zero-result demand."
      kpis={[]}
      resolveKpis={resolveKpis}
      chartTitle="Search Volume Trend"
    />
  );
}
