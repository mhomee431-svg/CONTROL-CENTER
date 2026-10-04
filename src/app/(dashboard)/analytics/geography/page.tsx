'use client';

import React from 'react';
import { AnalyticsSection } from '@/core/components/AnalyticsSection';

export default function AnalyticsGeographyPage() {
  return (
    <AnalyticsSection
      title="Geography Analytics"
      description="Regional demand, merchant coverage gaps, and hyperlocal density."
      kpis={[
        { label: 'COVERED CITIES', value: '—', color: '#EC4899' },
        { label: 'ACTIVE REGIONS', value: '—', color: '#0F52BA' },
        { label: 'COVERAGE GAPS', value: '—', color: '#EF4444' },
        { label: 'DEMAND HOTSPOTS', value: '—', color: '#F59E0B' },
      ]}
      chartTitle="Regional Activity Distribution"
    />
  );
}
