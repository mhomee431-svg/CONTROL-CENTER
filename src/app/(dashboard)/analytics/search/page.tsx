'use client';

import React from 'react';
import { AnalyticsPage, AnalyticsBreakdown } from '@/core/components/AnalyticsPage';
import { useSectionAnalytics } from '@/core/analytics/useSectionAnalytics';
import { SearchAnalytics } from '@/core/types/analytics';
import { API_ENDPOINTS } from '@/core/api/endpoints';

/**
 * Search Analytics.
 *
 * Metrics: Searches, Successful searches, Zero-result searches, Product opens,
 * Shop opens, Directions clicks — over the shared reporting window.
 *
 * Direction clicks are not collected by the platform and are reported as
 * "Not collected" rather than zero.
 */
export default function AnalyticsSearchPage() {
  const { data, isLoading, isError } = useSectionAnalytics<SearchAnalytics>(
    'search',
    API_ENDPOINTS.ANALYTICS.SEARCH
  );

  const breakdowns: AnalyticsBreakdown[] = [
    {
      title: 'Top Search Terms',
      items: (data?.top_search_terms ?? []).map((t) => ({ label: t.term, value: t.count })),
      emptyText: 'No searches in this window.',
    },
    {
      title: 'Zero-Result Queries',
      items: (data?.zero_result_queries ?? []).map((q) => ({ label: q.query, value: q.count })),
      emptyText: 'No zero-result searches in this window.',
    },
  ];

  return (
    <AnalyticsPage
      title="Search Analytics"
      description="Discovery funnel performance, match quality and zero-result demand."
      isLoading={isLoading}
      isError={isError}
      kpis={[
        { label: 'SEARCHES', value: data?.total_searches ?? null, color: '#0F52BA' },
        { label: 'SUCCESSFUL SEARCHES', value: data?.successful_searches ?? null, color: '#10B981' },
        { label: 'ZERO-RESULT SEARCHES', value: data?.zero_result_searches ?? null, color: '#EF4444' },
        {
          label: 'SEARCH SUCCESS RATE',
          value:
            data?.search_success_rate === null || data?.search_success_rate === undefined
              ? null
              : `${data.search_success_rate}%`,
          color: '#22C55E',
        },
        { label: 'UNIQUE SEARCHERS', value: data?.unique_searchers ?? null, color: '#A855F7' },
        { label: 'PRODUCT OPENS', value: data?.product_opens ?? null, color: '#14B8A6' },
        { label: 'SHOP OPENS', value: data?.shop_opens ?? null, color: '#EC4899' },
        { label: 'DIRECTIONS CLICKS', value: data?.directions ?? null, color: '#6366F1' },
      ]}
      chartTitle="Search Volume by Day"
      chartKey="search:volume"
      chartData={(data?.searches_by_day ?? []).map((d) => ({ label: d.date, value: d.count }))}
      breakdowns={breakdowns}
    />
  );
}
