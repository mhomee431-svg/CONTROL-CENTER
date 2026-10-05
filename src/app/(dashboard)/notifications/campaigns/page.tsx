'use client';

import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, Button } from '@mui/material';
import { useRouter } from 'next/navigation';
import { Megaphone } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';
import { NotificationCampaignItem } from '@/core/types/admin';

export default function NotificationCampaignsPage() {
  const router = useRouter();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });

  const { data, isLoading, refetch } = useQuery<{ items: NotificationCampaignItem[]; total: number }>({
    queryKey: ['admin', 'campaigns', paginationModel],
    queryFn: () =>
      apiClient<{ items: NotificationCampaignItem[]; total: number }>(API_ENDPOINTS.NOTIFICATIONS.CAMPAIGNS, {
        params: {
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
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
        if (c.recipients_sent == null && c.recipients_total == null) return 'N/A';
        return `${c.recipients_sent ?? 0} / ${c.recipients_total ?? 0}`;
      },
    },
    {
      field: 'status',
      headerName: 'Status',
      width: 130,
      renderCell: (params) => <StatusBadge status={(params.value as string) || 'SENT'} />,
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

      <AdminDataGrid
        rows={(data?.items || []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        searchPlaceholder="Search campaigns..."
        onRefresh={() => refetch()}
        onRowClick={(params) => router.push(ROUTES.NOTIFICATION_DETAIL(params.row.id as number))}
      />
    </Box>
  );
}
