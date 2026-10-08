'use client';

import React from 'react';
import { AnalyticsPage, AnalyticsBreakdown } from '@/core/components/AnalyticsPage';
import { useSectionAnalytics } from '@/core/analytics/useSectionAnalytics';
import { BusinessAnalytics } from '@/core/types/analytics';
import { API_ENDPOINTS } from '@/core/api/endpoints';

/**
 * Business (Shops) Analytics.
 *
 * Metrics: Active Shops, New Shops, Category distribution, Location
 * distribution, Inventory freshness, Product coverage — over the shared
 * reporting window.
 */
export default function AnalyticsShopsPage() {
  const { data, isLoading, isError } = useSectionAnalytics<BusinessAnalytics>(
    'businesses',
    API_ENDPOINTS.ANALYTICS.BUSINESSES
  );

  const breakdowns: AnalyticsBreakdown[] = [
    {
      title: 'Category Distribution',
      items: (data?.shops_by_category ?? []).map((c) => ({ label: c.category, value: c.count })),
    },
    {
      title: 'Location Distribution',
      items: (data?.shops_by_city ?? []).map((c) => ({ label: c.city, value: c.count })),
    },
    {
      title: 'Top Product Coverage',
      items: (data?.top_coverage_shops ?? []).map((s) => ({ label: s.name, value: s.products })),
      emptyText: 'No inventory recorded for any shop yet.',
    },
  ];

  return (
    <AnalyticsPage
      title="Business Analytics"
      description="Storefront activation, category and location distribution, inventory freshness and product coverage."
      isLoading={isLoading}
      isError={isError}
      kpis={[
        { label: 'ACTIVE SHOPS', value: data?.active_shops ?? null, color: '#10B981' },
        { label: 'NEW SHOPS', value: data?.new_shops ?? null, color: '#3B82F6' },
        { label: 'TOTAL SHOPS', value: data?.total_shops ?? null, color: '#F59E0B' },
        { label: 'PENDING VERIFICATION', value: data?.pending_shops ?? null, color: '#A855F7' },
        { label: 'FRESH INVENTORY SHOPS', value: data?.fresh_shops ?? null, color: '#22C55E' },
        { label: 'STALE INVENTORY SHOPS', value: data?.stale_shops ?? null, color: '#EF4444' },
        {
          label: 'AVG PRODUCT COVERAGE',
          value:
            data === undefined ? null : data.average_product_coverage.toLocaleString(),
          color: '#6366F1',
        },
      ]}
      chartTitle="New Shops by Day"
      chartKey="businesses:new-shops"
      chartData={(data?.new_shops_by_day ?? []).map((d) => ({ label: d.date, value: d.count }))}
      breakdowns={breakdowns}
    />
  );
}
