'use client';

import React from 'react';
import { AnalyticsSection } from '@/core/components/AnalyticsSection';

export default function AnalyticsProductsPage() {
  return (
    <AnalyticsSection
      title="Product Analytics"
      description="Catalog coverage, approval throughput, and product discovery performance."
      kpis={[
        { label: 'TOTAL PRODUCTS', value: '—', color: '#A855F7' },
        { label: 'PENDING APPROVAL', value: '—', color: '#F59E0B' },
        { label: 'APPROVED', value: '—', color: '#10B981' },
        { label: 'ARCHIVED', value: '—', color: '#64748B' },
      ]}
      chartTitle="Catalog Demand Distribution"
    />
  );
}
