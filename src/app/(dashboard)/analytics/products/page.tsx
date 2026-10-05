'use client';

import React from 'react';
import { AnalyticsSection } from '@/core/components/AnalyticsSection';

export default function AnalyticsProductsPage() {
  return (
    <AnalyticsSection
      title="Product Analytics"
      description="Catalog coverage, approval throughput, and product discovery performance."
      kpis={({ summary, metrics, isLoading }) => {
        const ready = !isLoading && (summary !== undefined || metrics !== undefined);
        const num = (v: number | undefined) => (!ready ? '…' : v != null ? v.toLocaleString() : '—');
        return [
          { label: 'TOTAL PRODUCTS', value: num(metrics?.total_products), color: '#A855F7' },
          { label: 'PENDING APPROVAL', value: num(metrics?.pending_approvals), color: '#F59E0B' },
          { label: 'MISSING PRICES', value: num(metrics?.products_missing_prices), color: '#10B981' },
          { label: 'INVENTORY RECORDS', value: num(metrics?.total_inventory_records), color: '#64748B' },
        ];
      }}
      chartTitle="Catalog Demand Distribution"
    />
  );
}
