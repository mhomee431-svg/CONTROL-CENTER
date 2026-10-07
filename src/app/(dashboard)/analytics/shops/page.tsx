'use client';

import React from 'react';
import { AnalyticsSection, AnalyticsKpi } from '@/core/components/AnalyticsSection';
import { DashboardMetrics } from '@/core/types/admin';

export default function AnalyticsShopsPage() {
  const resolveKpis = ({ metrics, isLoading }: { metrics?: DashboardMetrics; isLoading: boolean }): AnalyticsKpi[] => [
    { label: 'TOTAL SHOPS', value: isLoading ? '...' : (metrics?.total_shops ?? '—'), color: '#F59E0B' },
    { label: 'ACTIVE SHOPS', value: isLoading ? '...' : (metrics?.active_shops ?? '—'), color: '#10B981' },
    { label: 'STALE INVENTORY', value: isLoading ? '...' : (metrics?.stale_inventory_count ?? '—'), color: '#EF4444' },
    { label: 'SYNC FAILURES', value: isLoading ? '...' : (metrics?.sync_failures ?? '—'), color: '#6366F1' },
  ];

  return (
    <AnalyticsSection
      title="Shop Analytics"
      description="Storefront density, inventory freshness, and operational reliability."
      kpis={[]}
      resolveKpis={resolveKpis}
      chartTitle="Shop Inventory Update Trend"
    />
  );
}
