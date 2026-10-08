'use client';

import React from 'react';
import { AnalyticsPage, AnalyticsBreakdown } from '@/core/components/AnalyticsPage';
import { useSectionAnalytics } from '@/core/analytics/useSectionAnalytics';
import { ShopkeeperAnalytics } from '@/core/types/analytics';
import { API_ENDPOINTS } from '@/core/api/endpoints';

/**
 * Shopkeeper Analytics.
 *
 * Metrics: New Shopkeepers, Active Shopkeepers, Active Businesses, Product
 * Additions, Inventory Updates, Price Updates, Imports, POS Sync, Failed
 * Imports — over the shared reporting window.
 */
export default function AnalyticsShopkeepersPage() {
  const { data, isLoading, isError } = useSectionAnalytics<ShopkeeperAnalytics>(
    'shopkeepers',
    API_ENDPOINTS.ANALYTICS.SHOPKEEPERS
  );

  const growth = data?.shopkeeper_growth_rate;
  const growthHint =
    growth === null || growth === undefined
      ? undefined
      : growth >= 0
      ? `▲ ${growth}% vs previous period`
      : `▼ ${Math.abs(growth)}% vs previous period`;

  const breakdowns: AnalyticsBreakdown[] = [
    {
      title: 'Top Merchants by Storefronts',
      items: (data?.top_merchants ?? []).map((m) => ({ label: m.name, value: m.shops })),
      emptyText: 'No merchants with storefronts yet.',
    },
    {
      title: 'Verification Breakdown',
      items: (data?.verification_breakdown ?? []).map((v) => ({
        label: v.status,
        value: v.count,
      })),
    },
  ];

  return (
    <AnalyticsPage
      title="Shopkeeper Analytics"
      description="Merchant onboarding, activation and contribution to the catalog."
      isLoading={isLoading}
      isError={isError}
      kpis={[
        { label: 'NEW SHOPKEEPERS', value: data?.new_shopkeepers ?? null, color: '#10B981', hint: growthHint },
        { label: 'ACTIVE SHOPKEEPERS', value: data?.active_shopkeepers ?? null, color: '#0F52BA' },
        { label: 'ACTIVE BUSINESSES', value: data?.active_businesses ?? null, color: '#F59E0B' },
        { label: 'PRODUCT ADDITIONS', value: data?.product_additions ?? null, color: '#A855F7' },
        { label: 'INVENTORY UPDATES', value: data?.inventory_updates ?? null, color: '#6366F1' },
        { label: 'PRICE UPDATES', value: data?.price_updates ?? null, color: '#14B8A6' },
        { label: 'IMPORTS COMPLETED', value: data?.imports_completed ?? null, color: '#22C55E' },
        { label: 'FAILED IMPORTS', value: data?.imports_failed ?? null, color: '#EF4444' },
        { label: 'POS SYNC SUCCESS', value: data?.pos_sync_success ?? null, color: '#3B82F6' },
        { label: 'POS SYNC FAILURES', value: data?.pos_sync_failures ?? null, color: '#DC2626' },
      ]}
      chartTitle="New Shopkeepers by Day"
      chartKey="shopkeepers:onboarding"
      chartData={(data?.shopkeepers_by_day ?? []).map((d) => ({ label: d.date, value: d.count }))}
      breakdowns={breakdowns}
    />
  );
}
