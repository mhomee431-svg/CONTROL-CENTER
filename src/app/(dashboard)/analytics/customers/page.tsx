'use client';

import React from 'react';
import { AnalyticsSection, AnalyticsKpi } from '@/core/components/AnalyticsSection';
import { DashboardMetrics } from '@/core/types/admin';

export default function AnalyticsCustomersPage() {
  const resolveKpis = ({ metrics, isLoading }: { metrics?: DashboardMetrics; isLoading: boolean }): AnalyticsKpi[] => [
    { label: 'TOTAL CUSTOMERS', value: isLoading ? '...' : (metrics?.total_customers ?? '—'), color: '#3B82F6' },
    { label: 'ACTIVE SHOPS SERVING THEM', value: isLoading ? '...' : (metrics?.active_shops ?? '—'), color: '#10B981' },
    { label: 'PENDING VERIFICATION', value: isLoading ? '...' : (metrics?.pending_verification ?? '—'), color: '#A855F7' },
    { label: 'OPEN COMPLAINTS', value: isLoading ? '...' : (metrics?.open_complaints ?? '—'), color: '#EF4444' },
  ];

  return (
    <AnalyticsSection
      title="Customer Analytics"
      description="Acquisition, activation, and engagement trends across the customer base."
      kpis={[]}
      resolveKpis={resolveKpis}
      chartTitle="Customer Search Activity"
    />
  );
}
