'use client';

import React from 'react';
import { Box, Typography } from '@mui/material';
import { GridColDef } from '@mui/x-data-grid';
import { Ticket } from 'lucide-react';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { PromotionalCardItem } from '@/core/types/admin';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ContentResourceManager, ContentField } from '@/core/components/ContentResourceManager';
import { ROUTES } from '@/core/routes/routes';
import { validateExplicitUrl } from '@/core/notifications/deepLink';

const FIELDS: ContentField[] = [
  { name: 'title', label: 'Card Title', required: true },
  { name: 'description', label: 'Description', type: 'textarea' },
  { name: 'image_url', label: 'Image URL' },
  { name: 'cta_label', label: 'CTA Button Label', defaultValue: 'Explore' },
  {
    name: 'deep_link',
    label: 'Deep Link (optional)',
    type: 'deep_link',
    validate: (v) => {
      if (!v) return null;
      const r = validateExplicitUrl(v);
      return r.valid ? null : r.message || 'Invalid deep link';
    },
  },
  {
    name: 'status',
    label: 'Status',
    type: 'select',
    defaultValue: 'DRAFT',
    options: [
      { value: 'DRAFT', label: 'Draft' },
      { value: 'SCHEDULED', label: 'Scheduled' },
      { value: 'PUBLISHED', label: 'Published' },
      { value: 'ARCHIVED', label: 'Archived' },
    ],
  },
];

const COLUMNS: GridColDef[] = [
  { field: 'id', headerName: 'ID', width: 80 },
  {
    field: 'title',
    headerName: 'Promotional Card',
    flex: 1.5,
    minWidth: 200,
    renderCell: (params) => (
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
        <Ticket size={16} color="#EF4444" />
        <Typography variant="body2" sx={{ fontWeight: 600 }}>
          {params.value as string}
        </Typography>
      </Box>
    ),
  },
  { field: 'cta_label', headerName: 'CTA', flex: 0.8, minWidth: 110, valueFormatter: (v) => (v as string) || '—' },
  {
    field: 'deep_link',
    headerName: 'Deep Link',
    flex: 1.2,
    minWidth: 160,
    valueFormatter: (value) => (value as string) || '—',
  },
  {
    field: 'status',
    headerName: 'Status',
    width: 130,
    renderCell: (params) => <StatusBadge status={(params.value as string) || 'DRAFT'} />,
  },
];

export default function ContentPromotionsPage() {
  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Content & Announcements', href: ROUTES.CONTENT },
          { label: 'Promotional Cards' },
        ]}
      />
      <ContentResourceManager<PromotionalCardItem>
        title="Promotional Card Management"
        subtitle="Design in-app promotional cards. Every deep link is validated against supported admin routes."
        listEndpoint={API_ENDPOINTS.CONTENT.PROMOTIONS}
        baseEndpoint={API_ENDPOINTS.CONTENT.PROMOTIONS}
        detailEndpoint={API_ENDPOINTS.CONTENT.PROMOTION_DETAIL}
        queryKey="admin-content-promotions"
        columns={COLUMNS}
        fields={FIELDS}
        labelField="title"
        searchPlaceholder="Search promotional cards..."
        buildPayload={(draft) => ({
          title: draft.title,
          description: draft.description || null,
          image_url: draft.image_url || null,
          cta_label: draft.cta_label || 'Explore',
          deep_link: draft.deep_link || null,
          status: draft.status || 'DRAFT',
        })}
      />
    </Box>
  );
}