'use client';

import React from 'react';
import { Box, Typography } from '@mui/material';
import { GridColDef } from '@mui/x-data-grid';
import { HelpCircle } from 'lucide-react';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { FaqItem } from '@/core/types/admin';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ContentResourceManager, ContentField } from '@/core/components/ContentResourceManager';
import { ROUTES } from '@/core/routes/routes';

const FIELDS: ContentField[] = [
  { name: 'question', label: 'Question', required: true },
  { name: 'answer', label: 'Answer', type: 'textarea', required: true },
  { name: 'category', label: 'Category', helperText: 'Optional grouping label.' },
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
    field: 'question',
    headerName: 'Question',
    flex: 2,
    minWidth: 260,
    renderCell: (params) => (
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
        <HelpCircle size={16} color="#10B981" />
        <Typography variant="body2" sx={{ fontWeight: 600 }}>
          {params.value as string}
        </Typography>
      </Box>
    ),
  },
  { field: 'category', headerName: 'Category', flex: 1, minWidth: 130, valueFormatter: (v) => (v as string) || '—' },
  {
    field: 'audience',
    headerName: 'Audience',
    flex: 0.8,
    minWidth: 110,
    valueGetter: (_, row) => ((row as FaqItem).audience || 'all').toUpperCase(),
  },
  {
    field: 'status',
    headerName: 'Status',
    width: 130,
    renderCell: (params) => <StatusBadge status={(params.value as string) || 'PUBLISHED'} />,
  },
];

export default function ContentFaqsPage() {
  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Content & Announcements', href: ROUTES.CONTENT },
          { label: 'FAQs' },
        ]}
      />
      <ContentResourceManager<FaqItem>
        title="FAQ Management"
        subtitle="Curate the frequently asked questions surfaced in the customer and shopkeeper help centre."
        listEndpoint={API_ENDPOINTS.CONTENT.FAQS}
        baseEndpoint={API_ENDPOINTS.CONTENT.FAQS}
        detailEndpoint={API_ENDPOINTS.CONTENT.FAQ_DETAIL}
        queryKey="admin-content-faqs"
        columns={COLUMNS}
        fields={FIELDS}
        labelField="question"
        searchPlaceholder="Search FAQs..."
        buildPayload={(draft) => ({
          question: draft.question,
          answer: draft.answer,
          category: draft.category || null,
          audience: draft.audience || 'all',
          status: draft.status || 'PUBLISHED',
          sort_order: Number(draft.sort_order) || 0,
        })}
      />
    </Box>
  );
}