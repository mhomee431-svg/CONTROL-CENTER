'use client';

import React from 'react';
import { AnalyticsSection } from '@/core/components/AnalyticsSection';

export default function AnalyticsSearchPage() {
  return (
    <AnalyticsSection
      title="Search Analytics"
      description="Discovery funnel performance, match quality, and zero-result demand."
      kpis={({ summary, isLoading }) => {
        const ready = !isLoading && summary !== undefined;
        const num = (v: number | undefined) => (!ready ? '…' : v != null ? v.toLocaleString() : '—');
        const zeroCount = summary?.zero_result_queries?.reduce((sum, q) => sum + (q.count || 0), 0);
        return [
          { label: 'TOTAL SEARCHES', value: num(summary?.total_searches), color: '#0F52BA' },
          {
            label: 'SUCCESS RATE',
            value:
              !ready ? '…' : summary?.search_success_rate != null ? `${summary.search_success_rate}%` : '—',
            color: '#10B981',
          },
          { label: 'UNIQUE SEARCHERS', value: num(summary?.unique_searchers), color: '#A855F7' },
          { label: 'ZERO-RESULT QUERIES', value: num(zeroCount), color: '#EF4444' },
        ];
      }}
      chartTitle="Search Volume Trend"
    />
  );
}
