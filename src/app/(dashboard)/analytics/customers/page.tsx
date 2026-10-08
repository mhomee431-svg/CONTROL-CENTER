'use client';

import React from 'react';
import { AnalyticsPage, AnalyticsBreakdown } from '@/core/components/AnalyticsPage';
import { useSectionAnalytics } from '@/core/analytics/useSectionAnalytics';
import { CustomerAnalytics } from '@/core/types/analytics';
import { API_ENDPOINTS } from '@/core/api/endpoints';

/**
 * Customer Analytics.
 *
 * Metrics: New Customers, Active Users, Returning Users, Registrations,
 * Retention (where the backend can substantiate it), Searches, Product Views,
 * Shop Views, Directions, Favorites — over the shared 7D / 30D / 90D / Custom
 * window.
 *
 * Directions are reported as "Not collected": the platform does not record
 * them, so rendering a zero would be a lie. Retention is likewise only shown
 * when there is an eligible base to measure against.
 */
export default function AnalyticsCustomersPage() {
  const { data, isLoading, isError } = useSectionAnalytics<CustomerAnalytics>(
    'customers',
    API_ENDPOINTS.ANALYTICS.CUSTOMERS
  );

  const pct = (value: number | null | undefined) =>
    value === null || value === undefined ? null : `${value}%`;

  const growth = data?.registration_growth_rate;
  const growthHint =
    growth === null || growth === undefined
      ? undefined
      : growth >= 0
      ? `▲ ${growth}% vs previous period`
      : `▼ ${Math.abs(growth)}% vs previous period`;

  const breakdowns: AnalyticsBreakdown[] = [
    {
      title: 'Registrations by City',
      items: (data?.registrations_by_city ?? []).map((c) => ({ label: c.city, value: c.count })),
      emptyText: 'No registrations in this window.',
    },
    {
      title: 'Customers by Status',
      items: (data?.customers_by_status ?? []).map((s) => ({ label: s.status, value: s.count })),
    },
  ];

  return (
    <AnalyticsPage
      title="Customer Analytics"
      description="Acquisition, activation, engagement and retention across the customer base."
      isLoading={isLoading}
      isError={isError}
      kpis={[
        { label: 'NEW CUSTOMERS', value: data?.new_customers ?? null, color: '#3B82F6', hint: growthHint },
        { label: 'ACTIVE USERS', value: data?.active_users ?? null, color: '#10B981' },
        { label: 'RETURNING USERS', value: data?.returning_users ?? null, color: '#0F52BA' },
        { label: 'RETENTION RATE', value: pct(data?.retention_rate), color: '#F59E0B' },
        { label: 'TOTAL REGISTRATIONS', value: data?.total_customers ?? null, color: '#6366F1' },
        { label: 'SEARCHES THIS PERIOD', value: data?.searches ?? null, color: '#A855F7' },
        { label: 'PRODUCT VIEWS', value: data?.product_views ?? null, color: '#14B8A6' },
        { label: 'SHOP VIEWS', value: data?.shop_views ?? null, color: '#EC4899' },
        { label: 'DIRECTIONS', value: data?.directions ?? null, color: '#EF4444' },
        { label: 'FAVORITES', value: data?.favorites ?? null, color: '#EAB308' },
      ]}
      chartTitle="Registrations & Searches by Day"
      chartKey="customers:activity"
      chartData={(data?.registrations_by_day ?? []).map((d) => ({
        label: d.date,
        value: d.registrations,
      }))}
      breakdowns={breakdowns}
    />
  );
}
