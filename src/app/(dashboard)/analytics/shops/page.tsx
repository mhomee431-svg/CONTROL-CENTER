'use client';

import React from 'react';
import { AnalyticsSection } from '@/core/components/AnalyticsSection';

export default function AnalyticsShopsPage() {
  return (
    <AnalyticsSection
      title="Shop Analytics"
      description="Storefront density, inventory freshness, and operational reliability."
      kpis={[
        { label: 'TOTAL SHOPS', value: '—', color: '#F59E0B' },
        { label: 'ACTIVE SHOPS', value: '—', color: '#10B981' },
        { label: 'STALE INVENTORY', value: '—', color: '#EF4444' },
        { label: 'SYNC FAILURES', value: '—', color: '#6366F1' },
      ]}
      chartTitle="Shop Inventory Update Trend"
    />
  );
}
