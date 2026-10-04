'use client';

import React from 'react';
import { AnalyticsSection } from '@/core/components/AnalyticsSection';

export default function AnalyticsCustomersPage() {
  return (
    <AnalyticsSection
      title="Customer Analytics"
      description="Acquisition, activation, and engagement trends across the customer base."
      kpis={[
        { label: 'TOTAL CUSTOMERS', value: '—', color: '#3B82F6' },
        { label: 'ACTIVE CUSTOMERS', value: '—', color: '#10B981' },
        { label: 'NEW THIS PERIOD', value: '—', color: '#A855F7' },
        { label: 'SUSPENDED', value: '—', color: '#EF4444' },
      ]}
      chartTitle="Customer Search Activity"
    />
  );
}
