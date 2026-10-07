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
          { label: 'MISSING PRICES', value: num(metrics?.products_missing_prices), color: '#EF4444' },
          {
            label: 'TOP CATEGORY DEMAND',
            value:
              !ready
                ? '…'
                : summary?.top_categories_searched?.[0]
                ? `${summary.top_categories_searched[0].category} (${summary.top_categories_searched[0].count.toLocaleString()})`
                : '—',
            color: '#10B981',
          },
        ];
      }}
      chartTitle="Catalog Demand Distribution"
      secondaryListSource="top_categories_searched"
      secondaryListTitle="Top Categories Searched"
    />
  );
}
