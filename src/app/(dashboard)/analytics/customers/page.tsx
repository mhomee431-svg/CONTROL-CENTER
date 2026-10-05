'use client';

import React from 'react';
import { AnalyticsSection } from '@/core/components/AnalyticsSection';

export default function AnalyticsCustomersPage() {
  return (
    <AnalyticsSection
      title="Customer Analytics"
      description="Acquisition, activation, and engagement trends across the customer base."
      kpis={({ summary, metrics, isLoading }) => {
        const ready = !isLoading && (summary !== undefined || metrics !== undefined);
        const num = (v: number | undefined) => (!ready ? '…' : v != null ? v.toLocaleString() : '—');
        return [
          { label: 'TOTAL CUSTOMERS', value: num(metrics?.total_customers), color: '#3B82F6' },
          { label: 'ACTIVE SEARCHERS', value: num(summary?.unique_searchers), color: '#10B981' },
          { label: 'SEARCHES THIS PERIOD', value: num(summary?.total_searches), color: '#A855F7' },
          {
            label: 'SEARCH SUCCESS RATE',
            value:
              !ready ? '…' : summary?.search_success_rate != null ? `${summary.search_success_rate}%` : '—',
            color: '#EF4444',
          },
        ];
      }}
      chartTitle="Customer Search Activity"
    />
  );
}
