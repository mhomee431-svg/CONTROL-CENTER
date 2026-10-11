'use client';

import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, Button, Tabs, Tab } from '@mui/material';
import { useRouter } from 'next/navigation';
import { Megaphone } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';
import { NotificationCampaignItem } from '@/core/types/admin';

/**
 * Delivery-status tabs. Each tab is a real server-side `status` filter, so a
 * tab's list and total are the campaigns that genuinely carry that status —
 * never a client-side slice of another tab.
 */
type CampaignTab = 'ALL' | 'DRAFT' | 'SCHEDULED' | 'SENT' | 'FAILED';

const CAMPAIGN_TABS: ReadonlyArray<{ value: CampaignTab; label: string; status?: string }> = [
  { value: 'ALL', label: 'All' },
  { value: 'DRAFT', label: 'Drafts', status: 'DRAFT' },
  { value: 'SCHEDULED', label: 'Scheduled', status: 'SCHEDULED' },
  { value: 'SENT', label: 'Sent', status: 'SENT' },
  { value: 'FAILED', label: 'Failed', status: 'FAILED' },
];

export default function NotificationCampaignsPage() {
  const router = useRouter();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [tab, setTab] = useState<CampaignTab>('ALL');

  const statusFilter = CAMPAIGN_TABS.find((t) => t.value === tab)?.status;

  const { data, isLoading, isError, refetch } = useQuery<{ items: NotificationCampaignItem[]; total: number }>({
    queryKey: ['admin', 'campaigns', tab, paginationModel],
    queryFn: () =>
      apiClient<{ items: NotificationCampaignItem[]; total: number }>(API_ENDPOINTS.NOTIFICATIONS.CAMPAIGNS, {
        params: {
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
          status: statusFilter,
        },
      }),
    retry: false,
  });

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    {
      field: 'title',
      headerName: 'Campaign',
      flex: 1.5,
      minWidth: 180,
      valueGetter: (_, row) => (row as NotificationCampaignItem).title || 'Broadcast',
    },
    {
      field: 'audience',
      headerName: 'Audience',
      flex: 0.8,
      minWidth: 120,
      valueGetter: (_, row) => ((row as NotificationCampaignItem).audience || 'all').toUpperCase(),
    },
    {
      field: 'notification_type',
      headerName: 'Type',
      flex: 1,
      minWidth: 150,
      valueFormatter: (value) => String(value || '').replace(/_/g, ' '),
    },
    {
      field: 'recipients_sent',
      headerName: 'Delivered',
      width: 130,
      valueGetter: (_, row) => {
        const c = row as NotificationCampaignItem;
        // A campaign that has not gone out reports no delivery count at all,
        // rather than a misleading 0 / 0.
        if (c.recipients_sent == null) return 'Not sent';
        return `${c.recipients_sent} / ${c.recipients_total ?? 0}`;
      },
    },
    {
      field: 'status',
      headerName: 'Status',
      width: 130,
      renderCell: (params) => <StatusBadge status={(params.value as string) || 'SENT'} />,
    },
    {
      field: 'scheduled_at',
      headerName: 'Scheduled',
      flex: 1.2,
      minWidth: 170,
      valueFormatter: (value) =>
        value ? new Date(value as string).toLocaleString() : '—',
    },
    {
      field: 'created_at',
      headerName: 'Created',
      flex: 1.2,
      minWidth: 170,
      valueFormatter: (value) => (value ? new Date(value as string).toLocaleString() : 'N/A'),
    },
  ];

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Notifications', href: ROUTES.NOTIFICATIONS },
          { label: 'Campaigns' },
        ]}
      />
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', mb: 3, flexWrap: 'wrap', gap: 2 }}>
        <Box>
          <Typography variant="h5" sx={{ fontWeight: 700 }}>
            Notification Campaigns
          </Typography>
          <Typography variant="body2" color="text.secondary">
            History and performance of platform broadcasts and targeted campaigns.
          </Typography>
        </Box>
        <Button variant="contained" startIcon={<Megaphone size={16} />} onClick={() => router.push(ROUTES.NOTIFICATIONS)}>
          New Broadcast →
        </Button>
      </Box>

      {/* Delivery-status tabs — each is a real server-side status filter. */}
      <Tabs
        value={tab}
        onChange={(_, value: CampaignTab) => {
          setTab(value);
          setPaginationModel((prev) => ({ ...prev, page: 0 }));
        }}
        sx={{ mb: 2, borderBottom: '1px solid #E2E8F0' }}
      >
        {CAMPAIGN_TABS.map((t) => (
          <Tab key={t.value} value={t.value} label={t.label} />
        ))}
      </Tabs>

      <AdminDataGrid
        rows={(data?.items || []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        error={isError}
        errorMessage="Campaigns could not be loaded. The request failed — retry, and escalate if it keeps failing."
        searchPlaceholder="Search campaigns..."
        onRefresh={() => refetch()}
        onRowClick={(params) => router.push(ROUTES.NOTIFICATION_DETAIL(params.row.id as number))}
      />
    </Box>
  );
}
