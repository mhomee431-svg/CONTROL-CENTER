'use client';

import React from 'react';
import { AnalyticsSection, AnalyticsKpi } from '@/core/components/AnalyticsSection';
import { DashboardMetrics } from '@/core/types/admin';

export default function AnalyticsShopkeepersPage() {
  const resolveKpis = ({ metrics, isLoading }: { metrics?: DashboardMetrics; isLoading: boolean }): AnalyticsKpi[] => [
    { label: 'TOTAL SHOPS (MERCHANTS)', value: isLoading ? '...' : (metrics?.total_shops ?? '—'), color: '#10B981' },
    { label: 'VERIFIED / ACTIVE', value: isLoading ? '...' : (metrics?.active_shops ?? '—'), color: '#0F52BA' },
    { label: 'PENDING VERIFICATION', value: isLoading ? '...' : (metrics?.pending_verification ?? '—'), color: '#F59E0B' },
    { label: 'INVENTORY RECORDS', value: isLoading ? '...' : (metrics?.total_inventory_records ?? '—'), color: '#6366F1' },
  ];

  return (
    <AnalyticsSection
      title="Shopkeeper Analytics"
      description="Merchant onboarding, verification velocity, and inventory contribution."
      kpis={[]}
      resolveKpis={resolveKpis}
      chartTitle="Merchant Activity Trend"
    />
  );
}
