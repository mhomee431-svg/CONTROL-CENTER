'use client';

import React from 'react';
import { AnalyticsSection } from '@/core/components/AnalyticsSection';

export default function AnalyticsShopkeepersPage() {
  return (
    <AnalyticsSection
      title="Shopkeeper Analytics"
      description="Merchant onboarding, verification velocity, and inventory contribution."
      kpis={({ metrics, isLoading }) => {
        const ready = !isLoading && metrics !== undefined;
        const num = (v: number | undefined) => (!ready ? '…' : v != null ? v.toLocaleString() : '—');
        return [
          { label: 'TOTAL SHOPS', value: num(metrics?.total_shops), color: '#10B981' },
          { label: 'ACTIVE SHOPS', value: num(metrics?.active_shops), color: '#0F52BA' },
          { label: 'PENDING VERIFICATION', value: num(metrics?.pending_verification), color: '#F59E0B' },
          { label: 'ACTIVE SUBSCRIPTIONS', value: num(metrics?.active_subscriptions), color: '#6366F1' },
        ];
      }}
      chartTitle="Merchant Activity Trend"
    />
  );
}
