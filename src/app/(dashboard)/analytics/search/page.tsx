'use client';

import React from 'react';
import { AnalyticsSection } from '@/core/components/AnalyticsSection';

export default function AnalyticsSearchPage() {
  return (
    <AnalyticsSection
      title="Search Analytics"
      description="Discovery funnel performance, match quality, and zero-result demand."
      kpis={[
        { label: 'TOTAL SEARCHES', value: '—', color: '#0F52BA' },
        { label: 'SUCCESS RATE', value: '—', color: '#10B981' },
        { label: 'UNIQUE SEARCHERS', value: '—', color: '#A855F7' },
        { label: 'ZERO-RESULT QUERIES', value: '—', color: '#EF4444' },
      ]}
      chartTitle="Search Volume Trend"
    />
  );
}
