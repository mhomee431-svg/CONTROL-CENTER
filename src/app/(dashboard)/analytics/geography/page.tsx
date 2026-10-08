'use client';

import React from 'react';
import { AnalyticsPage, AnalyticsBreakdown } from '@/core/components/AnalyticsPage';
import { useSectionAnalytics } from '@/core/analytics/useSectionAnalytics';
import { GeographyAnalytics } from '@/core/types/analytics';
import { API_ENDPOINTS } from '@/core/api/endpoints';

/**
 * Geographic Analytics.
 *
 * Shows: Customer density, Shop density, Search density, Category density and
 * the Demand/coverage relation — all from aggregated backend counts. No raw
 * coordinate stream is ever downloaded; the backend returns pre-aggregated
 * buckets so the browser receives a handful of rows, not millions of points.
 */
export default function AnalyticsGeographyPage() {
  const { data, isLoading, isError } = useSectionAnalytics<GeographyAnalytics>(
    'geography',
    API_ENDPOINTS.ANALYTICS.GEOGRAPHY
  );

  // Demand/coverage: where searches outrun storefront coverage. Cities with a
  // demand-per-shop above 1 are under-served; null means no storefront exists.
  const demandItems = (data?.demand_coverage ?? [])
    .slice()
    .sort((a, b) => (b.demand_per_shop ?? Infinity) - (a.demand_per_shop ?? Infinity))
    .map((d) => ({
      label: d.city,
      value:
        d.demand_per_shop === null
          ? 'No shops'
          : `${d.demand_per_shop.toLocaleString()} searches / shop`,
    }));

  const breakdowns: AnalyticsBreakdown[] = [
    {
      title: 'Shop Density by City',
      items: (data?.shops_by_city ?? []).map((c) => ({ label: c.city, value: c.count })),
      emptyText: 'No mapped shops yet.',
    },
    {
      title: 'Customer Density by City',
      items: (data?.customers_by_city ?? []).map((c) => ({ label: c.city, value: c.count })),
    },
    {
      title: 'Search Density by Location',
      items: (data?.searches_by_location ?? []).map((l) => ({ label: l.location, value: l.count })),
      emptyText: 'No located searches in this window.',
    },
    {
      title: 'Category Density',
      items: (data?.category_density ?? []).map((c) => ({
        label: `${c.city} — ${c.category}`,
        value: c.count,
      })),
    },
    {
      title: 'Demand / Coverage Relation',
      items: demandItems,
      emptyText: 'No demand or coverage data in this window.',
    },
  ];

  return (
    <AnalyticsPage
      title="Geography Analytics"
      description="Regional demand, merchant coverage and hyperlocal density, from aggregated data."
      isLoading={isLoading}
      isError={isError}
      kpis={[
        { label: 'COVERED CITIES', value: data?.covered_cities ?? null, color: '#EC4899' },
        { label: 'COVERED STATES', value: data?.covered_states ?? null, color: '#0F52BA' },
        {
          label: 'MAPPED SHOPS',
          value: (data?.shops_by_city ?? []).reduce((sum, c) => sum + c.count, 0),
          color: '#10B981',
        },
        {
          label: 'TOP DEMAND ZONE',
          value:
            data === undefined || (data.searches_by_location ?? []).length === 0
              ? null
              : data.searches_by_location[0].location,
          color: '#F59E0B',
        },
      ]}
      chartTitle="Shop Density by City"
      chartKey="geography:shop-density"
      chartData={(data?.shops_by_city ?? []).slice(0, 10).map((c) => ({
        label: c.city,
        value: c.count,
      }))}
      breakdowns={breakdowns}
    />
  );
}
