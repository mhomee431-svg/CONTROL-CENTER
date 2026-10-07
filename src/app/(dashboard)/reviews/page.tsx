'use client';

import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, Alert, Chip } from '@mui/material';
import { useRouter } from 'next/navigation';
import { MessageSquare, Star as StarIcon, Flag } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { ReviewItem } from '@/core/types/reviews';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';
import { resolveReviewState, isReported, isFlagged, isHidden, reportCount, displayRating } from '@/core/reviews/moderation';

/** Queue tabs mirroring the moderation contract. */
const QUEUE_TABS = [
  { value: 'ALL', label: 'Reviews' },
  { value: 'REPORTED', label: 'Reported' },
  { value: 'FLAGGED', label: 'Flagged' },
  { value: 'HIDDEN', label: 'Hidden' },
] as const;

type QueueTab = (typeof QUEUE_TABS)[number]['value'];

export default function ReviewsPage() {
  const router = useRouter();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [queueTab, setQueueTab] = useState<QueueTab>('ALL');

  const { data, isLoading, isError, refetch } = useQuery<{ items: ReviewItem[]; total: number }>({
    queryKey: ['admin', 'reviews', paginationModel, queueTab],
    queryFn: () =>
      apiClient<{ items: ReviewItem[]; total: number }>(API_ENDPOINTS.REVIEWS.LIST, {
        params: {
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
          state: queueTab === 'ALL' ? undefined : queueTab,
        },
      }),
    retry: false,
  });

  const items = data?.items || [];
  const counts = {
    reported: items.filter(isReported).length,
    flagged: items.filter(isFlagged).length,
    hidden: items.filter(isHidden).length,
  };

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    {
      field: 'entity_name',
      headerName: 'Reviewed',
      flex: 1.4,
      minWidth: 180,
      renderCell: (params) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <MessageSquare size={16} color="#0F52BA" />
          <Typography variant="body2" sx={{ fontWeight: 600 }}>
            {(params.value as string) || `#${params.row.entity_id}`}
          </Typography>
        </Box>
      ),
    },
    {
      field: 'rating',
      headerName: 'Rating',
      width: 110,
      renderCell: (params) => {
        const stars = displayRating(params.row as ReviewItem);
        return stars ? (
          <Chip
            size="small"
            icon={<StarIcon size={12} />}
            label={`${stars}/5`}
            color={stars <= 2 ? 'error' : stars === 3 ? 'warning' : 'success'}
            variant="outlined"
          />
        ) : (
          <Typography variant="body2" color="text.secondary">—</Typography>
        );
      },
    },
    {
      field: 'report_count',
      headerName: 'Reports',
      width: 90,
      renderCell: (params) => {
        const count = reportCount(params.row as ReviewItem);
        return count > 0 ? (
          <Chip size="small" icon={<Flag size={12} />} label={count} color="error" />
        ) : (
          <Typography variant="body2" color="text.secondary">—</Typography>
        );
      },
    },
    {
      field: 'moderation_state',
      headerName: 'State',
      width: 130,
      renderCell: (params) => <StatusBadge status={resolveReviewState(params.row as ReviewItem)} />,
    },
    {
      field: 'created_at',
      headerName: 'Submitted',
      flex: 1.1,
      minWidth: 160,
      valueFormatter: (value) => (value ? new Date(value as string).toLocaleString() : 'N/A'),
    },
  ];

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Reviews & Moderation' },
        ]}
      />
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Reviews & Moderation
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Customer reviews reported or flagged by users or the platform, awaiting a moderation decision.
        </Typography>
      </Box>

      {/* Summary counts for the loaded queue page */}
      <Box sx={{ display: 'flex', gap: 1, mb: 2, flexWrap: 'wrap' }}>
        <Chip size="small" label={"Reported: " + counts.reported} color="error" variant="outlined" />
        <Chip size="small" label={"Flagged: " + counts.flagged} color="warning" variant="outlined" />
        <Chip size="small" label={"Hidden: " + counts.hidden} color="default" variant="outlined" />
      </Box>

      {/* Queue tabs — the four documented moderation queues */}
      <Box sx={{ display: 'flex', gap: 1, mb: 2, flexWrap: 'wrap' }}>
        {QUEUE_TABS.map((tab) => (
          <Box
            key={tab.value}
            component="button"
            type="button"
            onClick={() => {
              setQueueTab(tab.value);
              setPaginationModel((p) => ({ ...p, page: 0 }));
            }}
            sx={{
              px: 1.5, py: 0.5, borderRadius: '20px', fontSize: '0.75rem', fontWeight: 600,
              fontFamily: 'inherit', cursor: 'pointer', border: '1px solid',
              borderColor: queueTab === tab.value ? 'primary.main' : '#CBD5E1',
              backgroundColor: queueTab === tab.value ? '#EFF6FF' : '#FFFFFF',
              color: queueTab === tab.value ? 'primary.main' : '#475569',
              '&:hover': { borderColor: 'primary.main' },
            }}
          >
            {tab.label}
          </Box>
        ))}
      </Box>

      {isError && (
        <Alert severity="error" sx={{ mb: 2 }}>
          The reviews endpoint is unavailable on this backend, or you lack the reviews capability.
        </Alert>
      )}

      <AdminDataGrid
        rows={items as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? items.length}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        searchPlaceholder="Search reviews..."
        onRefresh={() => refetch()}
        onRowClick={(params) => router.push(ROUTES.REVIEW_DETAIL(params.row.id as number))}
      />
    </Box>
  );
}