'use client';

import React from 'react';
import { Box, Typography } from '@mui/material';
import { GridColDef } from '@mui/x-data-grid';
import { Image as ImageIcon } from 'lucide-react';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { HomeBannerItem } from '@/core/types/admin';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ContentResourceManager, ContentField } from '@/core/components/ContentResourceManager';
import { ROUTES } from '@/core/routes/routes';
import { validateExplicitUrl } from '@/core/notifications/deepLink';

const FIELDS: ContentField[] = [
  { name: 'title', label: 'Banner Title', required: true },
  { name: 'subtitle', label: 'Subtitle' },
  { name: 'image_url', label: 'Image URL', required: true, helperText: 'Backend-hosted asset URL (S3/CDN).' },
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
  { name: 'placement', label: 'Placement', defaultValue: 'HOME_TOP' },
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
  { name: 'sort_order', label: 'Sort Order', defaultValue: '0' },
];

const COLUMNS: GridColDef[] = [
  { field: 'id', headerName: 'ID', width: 80 },
  {
    field: 'title',
    headerName: 'Banner',
    flex: 1.5,
    minWidth: 200,
    renderCell: (params) => (
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
        <ImageIcon size={16} color="#0F52BA" />
        <Typography variant="body2" sx={{ fontWeight: 600 }}>
          {params.value as string}
        </Typography>
      </Box>
    ),
  },
  { field: 'placement', headerName: 'Placement', flex: 1, minWidth: 140 },
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
  {
    field: 'updated_at',
    headerName: 'Updated',
    flex: 1,
    minWidth: 160,
    valueFormatter: (value) => (value ? new Date(value as string).toLocaleString() : 'N/A'),
  },
];

export default function ContentBannersPage() {
  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Content & Announcements', href: ROUTES.CONTENT },
          { label: 'Home Banners' },
        ]}
      />
      <ContentResourceManager<HomeBannerItem>
        title="Home Banner Management"
        subtitle="Manage the promotional banners displayed on the customer home screen."
        listEndpoint={API_ENDPOINTS.CONTENT.BANNERS}
        baseEndpoint={API_ENDPOINTS.CONTENT.BANNERS}
        detailEndpoint={API_ENDPOINTS.CONTENT.BANNER_DETAIL}
        queryKey="admin-content-banners"
        columns={COLUMNS}
        fields={FIELDS}
        labelField="title"
        searchPlaceholder="Search banners..."
        buildPayload={(draft) => ({
          title: draft.title,
          subtitle: draft.subtitle || null,
          image_url: draft.image_url,
          deep_link: draft.deep_link || null,
          placement: draft.placement || 'HOME_TOP',
          status: draft.status || 'DRAFT',
          sort_order: Number(draft.sort_order) || 0,
        })}
      />
    </Box>
  );
}