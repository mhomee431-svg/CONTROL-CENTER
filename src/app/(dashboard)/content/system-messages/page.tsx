'use client';

import React from 'react';
import { Box, Typography, Chip } from '@mui/material';
import { GridColDef } from '@mui/x-data-grid';
import { AlertTriangle } from 'lucide-react';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { SystemMessageItem } from '@/core/types/admin';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ContentResourceManager, ContentField } from '@/core/components/ContentResourceManager';
import { ROUTES } from '@/core/routes/routes';

const SEVERITY_COLORS: Record<string, 'info' | 'warning' | 'error'> = {
  INFO: 'info',
  WARNING: 'warning',
  CRITICAL: 'error',
};

const FIELDS: ContentField[] = [
  { name: 'title', label: 'Message Title', required: true },
  { name: 'body', label: 'Message Body', type: 'textarea', required: true },
  {
    name: 'severity',
    label: 'Severity',
    type: 'select',
    defaultValue: 'INFO',
    options: [
      { value: 'INFO', label: 'Info' },
      { value: 'WARNING', label: 'Warning' },
      { value: 'CRITICAL', label: 'Critical' },
    ],
  },
  {
    name: 'status',
    label: 'Status',
    type: 'select',
    defaultValue: 'PUBLISHED',
    options: [
      { value: 'DRAFT', label: 'Draft' },
      { value: 'SCHEDULED', label: 'Scheduled' },
      { value: 'PUBLISHED', label: 'Published' },
      { value: 'ARCHIVED', label: 'Archived' },
    ],
  },
  {
    name: 'is_active',
    label: 'Active (true/false)',
    defaultValue: 'true',
    validate: (v) => (v === '' || v === 'true' || v === 'false' ? null : 'Enter true or false.'),
  },
];

const COLUMNS: GridColDef[] = [
  { field: 'id', headerName: 'ID', width: 80 },
  {
    field: 'title',
    headerName: 'System Message',
    flex: 1.5,
    minWidth: 220,
    renderCell: (params) => (
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
        <AlertTriangle size={16} color="#6366F1" />
        <Typography variant="body2" sx={{ fontWeight: 600 }}>
          {params.value as string}
        </Typography>
      </Box>
    ),
  },
  {
    field: 'severity',
    headerName: 'Severity',
    width: 130,
    renderCell: (params) => {
      const sev = ((params.value as string) || 'INFO').toUpperCase();
      return <Chip size="small" label={sev} color={SEVERITY_COLORS[sev] || 'info'} variant="outlined" />;
    },
  },
  {
    field: 'is_active',
    headerName: 'Active',
    width: 100,
    renderCell: (params) => <StatusBadge status={params.value ? 'ACTIVE' : 'INACTIVE'} />,
  },
  {
    field: 'status',
    headerName: 'Status',
    width: 130,
    renderCell: (params) => <StatusBadge status={(params.value as string) || 'PUBLISHED'} />,
  },
];

export default function ContentSystemMessagesPage() {
  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Content & Announcements', href: ROUTES.CONTENT },
          { label: 'System Messages' },
        ]}
      />
      <ContentResourceManager<SystemMessageItem>
        title="System Message Management"
        subtitle="Broadcast operational banners such as scheduled maintenance, degradations and outage notices."
        listEndpoint={API_ENDPOINTS.CONTENT.SYSTEM_MESSAGES}
        baseEndpoint={API_ENDPOINTS.CONTENT.SYSTEM_MESSAGES}
        detailEndpoint={API_ENDPOINTS.CONTENT.SYSTEM_MESSAGE_DETAIL}
        queryKey="admin-content-system-messages"
        columns={COLUMNS}
        fields={FIELDS}
        labelField="title"
        searchPlaceholder="Search system messages..."
        buildPayload={(draft) => ({
          title: draft.title,
          body: draft.body,
          severity: draft.severity || 'INFO',
          status: draft.status || 'PUBLISHED',
          is_active: draft.is_active === 'true',
        })}
      />
    </Box>
  );
}