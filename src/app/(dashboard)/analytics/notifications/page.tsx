'use client';

import React from 'react';
import { AnalyticsPage, AnalyticsBreakdown } from '@/core/components/AnalyticsPage';
import { useSectionAnalytics } from '@/core/analytics/useSectionAnalytics';
import { NotificationAnalytics } from '@/core/types/analytics';
import { API_ENDPOINTS } from '@/core/api/endpoints';

/**
 * Notification Analytics.
 *
 * Where the backend supports it: Sent, Delivered, Opened, Clicked, Failed.
 * The platform records per-campaign recipient totals (sent / failed) but does
 * NOT record delivery receipts, opens or clicks. Those metrics are reported by
 * the backend as `null` and rendered here as "Not collected" — the section
 * never fabricates delivery/open data.
 */
export default function AnalyticsNotificationsPage() {
  const { data, isLoading, isError } = useSectionAnalytics<NotificationAnalytics>(
    'notifications',
    API_ENDPOINTS.ANALYTICS.NOTIFICATIONS
  );

  const breakdowns: AnalyticsBreakdown[] = [
    {
      title: 'Campaigns by Status',
      items: (data?.campaigns_by_status ?? []).map((s) => ({ label: s.status, value: s.count })),
      emptyText: 'No campaigns recorded yet.',
    },
    {
      title: 'Campaigns by Audience',
      items: (data?.campaigns_by_audience ?? []).map((a) => ({ label: a.audience, value: a.count })),
    },
  ];

  return (
    <AnalyticsPage
      title="Notification Analytics"
      description="Campaign dispatch and recipient outcomes for the selected window."
      isLoading={isLoading}
      isError={isError}
      notice="Delivered, Opened and Clicked are not recorded by the platform and are shown as Not collected rather than as zero."
      kpis={[
        { label: 'CAMPAIGNS SENT', value: data?.campaigns_sent ?? null, color: '#0F52BA' },
        { label: 'TOTAL CAMPAIGNS', value: data?.total_campaigns ?? null, color: '#6366F1' },
        { label: 'RECIPIENTS TARGETED', value: data?.recipients_total ?? null, color: '#A855F7' },
        { label: 'SENT', value: data?.recipients_sent ?? null, color: '#10B981' },
        { label: 'FAILED', value: data?.recipients_failed ?? null, color: '#EF4444' },
        { label: 'DELIVERED', value: data?.recipients_delivered ?? null, color: '#14B8A6' },
        { label: 'OPENED', value: data?.recipients_opened ?? null, color: '#F59E0B' },
        { label: 'CLICKED', value: data?.recipients_clicked ?? null, color: '#EC4899' },
      ]}
      chartTitle="Campaigns Sent by Day"
      chartKey="notifications:dispatch"
      chartData={(data?.campaigns_sent_by_day ?? []).map((d) => ({ label: d.date, value: d.count }))}
      breakdowns={breakdowns}
    />
  );
}
