'use client';

import React from 'react';
import { Box, Typography, Chip } from '@mui/material';
import { GridColDef } from '@mui/x-data-grid';
import { Megaphone, Pin } from 'lucide-react';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AnnouncementItem } from '@/core/types/admin';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ContentResourceManager, ContentField } from '@/core/components/ContentResourceManager';
import { ROUTES } from '@/core/routes/routes';

const FIELDS: ContentField[] = [
  { name: 'title', label: 'Announcement Title', required: true },
  { name: 'body', label: 'Announcement Body', type: 'textarea', required: true },
  {
    name: 'audience',
    label: 'Audience',
    type: 'select',
    defaultValue: 'all',
    options: [
      { value: 'all', label: 'All Platform Users' },
      { value: 'customer', label: 'Customers Only' },
      { value: 'shopkeeper', label: 'Shopkeepers Only' },
    ],
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
  {
    name: 'is_pinned',
    label: 'Pin to top (true/false)',
    defaultValue: 'false',
    validate: (v) => (v === '' || v === 'true' || v === 'false' ? null : 'Enter true or false.'),
  },
];

const COLUMNS: GridColDef[] = [
  { field: 'id', headerName: 'ID', width: 80 },
  {
    field: 'title',
    headerName: 'Announcement',
    flex: 1.5,
    minWidth: 220,
    renderCell: (params) => (
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
        <Megaphone size={16} color="#8B5CF6" />
        <Typography variant="body2" sx={{ fontWeight: 600 }}>
          {params.value as string}
        </Typography>
        {(params.row as AnnouncementItem).is_pinned && <Pin size={13} color="#F59E0B" />}
      </Box>
    ),
  },
  {
    field: 'audience',
    headerName: 'Audience',
    flex: 0.8,
    minWidth: 120,
    valueGetter: (_, row) => ((row as AnnouncementItem).audience || 'all').toUpperCase(),
  },
  {
    field: 'status',
    headerName: 'Status',
    width: 130,
    renderCell: (params) => <StatusBadge status={(params.value as string) || 'DRAFT'} />,
  },
  {
    field: 'published_at',
    headerName: 'Published',
    flex: 1,
    minWidth: 160,
    valueFormatter: (value) => (value ? new Date(value as string).toLocaleString() : 'Not published'),
  },
];

export default function ContentAnnouncementsPage() {
  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Content & Announcements', href: ROUTES.CONTENT },
          { label: 'Announcements' },
        ]}
      />
      <ContentResourceManager<AnnouncementItem>
        title="Announcement Management"
        subtitle="Publish targeted platform announcements to customers and shopkeepers."
        listEndpoint={API_ENDPOINTS.CONTENT.ANNOUNCEMENTS}
        baseEndpoint={API_ENDPOINTS.CONTENT.ANNOUNCEMENTS}
        detailEndpoint={API_ENDPOINTS.CONTENT.ANNOUNCEMENT_DETAIL}
        queryKey="admin-content-announcements"
        columns={COLUMNS}
        fields={FIELDS}
        labelField="title"
        searchPlaceholder="Search announcements..."
        buildPayload={(draft) => ({
          title: draft.title,
          body: draft.body,
          audience: draft.audience || 'all',
          status: draft.status || 'DRAFT',
          is_pinned: draft.is_pinned === 'true',
        })}
      />
    </Box>
  );
}