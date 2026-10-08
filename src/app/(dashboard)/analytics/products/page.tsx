'use client';

import React from 'react';
import { AnalyticsPage, AnalyticsBreakdown } from '@/core/components/AnalyticsPage';
import { useSectionAnalytics } from '@/core/analytics/useSectionAnalytics';
import { ProductAnalytics } from '@/core/types/analytics';
import { API_ENDPOINTS } from '@/core/api/endpoints';

/**
 * Product Analytics.
 *
 * Metrics: Top searched products, Top viewed products, Most available
 * products, Low coverage products, Products with no shop, Products with stale
 * inventory — over the shared reporting window.
 */
export default function AnalyticsProductsPage() {
  const { data, isLoading, isError } = useSectionAnalytics<ProductAnalytics>(
    'products',
    API_ENDPOINTS.ANALYTICS.PRODUCTS
  );

  const breakdowns: AnalyticsBreakdown[] = [
    {
      title: 'Top Searched Products',
      items: (data?.top_searched_products ?? []).map((p) => ({ label: p.name, value: p.count })),
      emptyText: 'No product-name searches in this window.',
    },
    {
      title: 'Top Viewed Products',
      items: (data?.top_viewed_products ?? []).map((p) => ({ label: p.name, value: p.count })),
    },
    {
      title: 'Most Available Products',
      items: (data?.most_available_products ?? []).map((p) => ({ label: p.name, value: p.count })),
    },
    {
      title: 'Products by Category',
      items: (data?.products_by_category ?? []).map((c) => ({ label: c.category, value: c.count })),
    },
  ];

  return (
    <AnalyticsPage
      title="Product Analytics"
      description="Catalog demand, coverage and hygiene across the product master."
      isLoading={isLoading}
      isError={isError}
      kpis={[
        { label: 'TOTAL PRODUCTS', value: data?.total_products ?? null, color: '#A855F7' },
        { label: 'ACTIVE PRODUCTS', value: data?.active_products ?? null, color: '#10B981' },
        { label: 'PENDING APPROVAL', value: data?.pending_products ?? null, color: '#F59E0B' },
        { label: 'PRODUCTS WITH NO SHOP', value: data?.products_with_no_shop ?? null, color: '#EF4444' },
        { label: 'LOW COVERAGE PRODUCTS', value: data?.low_coverage_products ?? null, color: '#DC2626' },
        {
          label: 'PRODUCTS WITH STALE INVENTORY',
          value: data?.products_with_stale_inventory ?? null,
          color: '#6366F1',
        },
      ]}
      chartTitle="Products Added by Day"
      chartKey="products:additions"
      chartData={(data?.products_added_by_day ?? []).map((d) => ({ label: d.date, value: d.count }))}
      breakdowns={breakdowns}
    />
  );
}
