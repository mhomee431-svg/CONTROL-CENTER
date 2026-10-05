'use client';

import React from 'react';
import { AnalyticsSection } from '@/core/components/AnalyticsSection';

export default function AnalyticsShopsPage() {
  return (
    <AnalyticsSection
      title="Shop Analytics"
      description="Storefront density, inventory freshness, and operational reliability."
      kpis={({ metrics, isLoading }) => {
        const ready = !isLoading && metrics !== undefined;
        const num = (v: number | undefined) => (!ready ? '…' : v != null ? v.toLocaleString() : '—');
        return [
          { label: 'TOTAL SHOPS', value: num(metrics?.total_shops), color: '#F59E0B' },
          { label: 'ACTIVE SHOPS', value: num(metrics?.active_shops), color: '#10B981' },
          { label: 'STALE INVENTORY', value: num(metrics?.stale_inventory_count), color: '#EF4444' },
          { label: 'SYNC FAILURES', value: num(metrics?.sync_failures), color: '#6366F1' },
        ];
      }}
      chartTitle="Shop Inventory Update Trend"
    />
  );
}
