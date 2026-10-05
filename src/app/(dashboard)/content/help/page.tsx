'use client';

import React from 'react';
import { Box, Typography } from '@mui/material';
import { GridColDef } from '@mui/x-data-grid';
import { BookOpen } from 'lucide-react';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { HelpContentItem } from '@/core/types/admin';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ContentResourceManager, ContentField } from '@/core/components/ContentResourceManager';
import { ROUTES } from '@/core/routes/routes';

const FIELDS: ContentField[] = [
  { name: 'title', label: 'Article Title', required: true },
  { name: 'slug', label: 'URL Slug', helperText: 'Lowercase, hyphen-separated. Used in the help centre URL.' },
  { name: 'section', label: 'Section', helperText: 'e.g. Getting Started, Billing, Inventory.' },
  { name: 'body', label: 'Article Body', type: 'textarea', required: true },
  {
    name: 'status',
    label: 'Status',
    type: 'select',
    defaultValue: 'PUBLISHED',
    options: [
      { value: 'DRAFT', label: 'Draft' },
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
    headerName: 'Article',
    flex: 2,
    minWidth: 240,
    renderCell: (params) => (
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
        <BookOpen size={16} color="#F59E0B" />
        <Typography variant="body2" sx={{ fontWeight: 600 }}>
          {params.value as string}
        </Typography>
      </Box>
    ),
  },
  { field: 'section', headerName: 'Section', flex: 1, minWidth: 140, valueFormatter: (v) => (v as string) || '—' },
  { field: 'slug', headerName: 'Slug', flex: 1, minWidth: 140, valueFormatter: (v) => (v as string) || '—' },
  {
    field: 'status',
    headerName: 'Status',
    width: 130,
    renderCell: (params) => <StatusBadge status={(params.value as string) || 'PUBLISHED'} />,
  },
];

export default function ContentHelpPage() {
  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Content & Announcements', href: ROUTES.CONTENT },
          { label: 'Help Content' },
        ]}
      />
      <ContentResourceManager<HelpContentItem>
        title="Help Content Management"
        subtitle="Author structured help articles and onboarding guides for the help centre."
        listEndpoint={API_ENDPOINTS.CONTENT.HELP}
        baseEndpoint={API_ENDPOINTS.CONTENT.HELP}
        detailEndpoint={API_ENDPOINTS.CONTENT.HELP_DETAIL}
        queryKey="admin-content-help"
        columns={COLUMNS}
        fields={FIELDS}
        labelField="title"
        searchPlaceholder="Search help articles..."
        buildPayload={(draft) => ({
          title: draft.title,
          slug: draft.slug || null,
          section: draft.section || null,
          body: draft.body,
          status: draft.status || 'PUBLISHED',
          sort_order: Number(draft.sort_order) || 0,
        })}
      />
    </Box>
  );
}