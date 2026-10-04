'use client';

import React from 'react';
import { AnalyticsSection } from '@/core/components/AnalyticsSection';

export default function AnalyticsShopkeepersPage() {
  return (
    <AnalyticsSection
      title="Shopkeeper Analytics"
      description="Merchant onboarding, verification velocity, and inventory contribution."
      kpis={[
        { label: 'TOTAL SHOPKEEPERS', value: '—', color: '#10B981' },
        { label: 'VERIFIED', value: '—', color: '#0F52BA' },
        { label: 'PENDING', value: '—', color: '#F59E0B' },
        { label: 'ACTIVE SHOPS', value: '—', color: '#6366F1' },
      ]}
      chartTitle="Merchant Activity Trend"
    />
  );
}
