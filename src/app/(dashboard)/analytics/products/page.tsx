'use client';

import React from 'react';
import { AnalyticsSection, AnalyticsKpi } from '@/core/components/AnalyticsSection';
import { DashboardMetrics } from '@/core/types/admin';
import { AnalyticsSummary } from '@/core/types/analytics';

export default function AnalyticsProductsPage() {
  const resolveKpis = ({
    summary,
    metrics,
    isLoading,
  }: {
    summary?: AnalyticsSummary;
    metrics?: DashboardMetrics;
    isLoading: boolean;
  }): AnalyticsKpi[] => [
    { label: 'TOTAL PRODUCTS', value: isLoading ? '...' : (metrics?.total_products ?? '—'), color: '#A855F7' },
    { label: 'PENDING APPROVAL', value: isLoading ? '...' : (metrics?.pending_approvals ?? '—'), color: '#F59E0B' },
    {
      label: 'MISSING PRICES',
      value: isLoading ? '...' : (metrics?.products_missing_prices ?? '—'),
      color: '#EF4444',
    },
    {
      label: 'TOP CATEGORY DEMAND',
      value: isLoading
        ? '...'
        : summary?.top_categories_searched?.[0]
        ? `${summary.top_categories_searched[0].category} (${summary.top_categories_searched[0].count.toLocaleString()})`
        : '—',
      color: '#10B981',
    },
  ];

  return (
    <AnalyticsSection
      title="Product Analytics"
      description="Catalog coverage, approval throughput, and product discovery performance."
      kpis={[]}
      resolveKpis={resolveKpis}
      chartTitle="Catalog Demand Distribution"
      secondaryListSource="top_categories_searched"
      secondaryListTitle="Top Categories Searched"
    />
  );
}
