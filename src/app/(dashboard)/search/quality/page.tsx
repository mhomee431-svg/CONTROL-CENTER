'use client';

import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography } from '@mui/material';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { AnalyticsSummary } from '@/core/types/analytics';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';
import { useDateRange } from '@/core/filters/DateRangeContext';

interface QualityRow {
  id: number;
  term: string;
  count: number;
  location?: string;
}

export default function SearchQualityPage() {
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [search, setSearch] = useState('');

  const { params: dateParams } = useDateRange();

  const { data, isLoading, isError, refetch } = useQuery<AnalyticsSummary>({
    queryKey: ['admin', 'analytics', 'summary', dateParams],
    queryFn: () =>
      apiClient<AnalyticsSummary>(API_ENDPOINTS.DASHBOARD.ANALYTICS_SUMMARY, {
        params: dateParams,
      }),
    retry: false,
  });

  // The summary payload is a single aggregate list, so filtering happens
  // client-side here (unlike the server-paginated registries).
  const rows: QualityRow[] = (data?.zero_result_queries || [])
    .map((q, idx) => ({
      id: idx + 1,
      term: q.query,
      count: q.count,
      location: q.location,
    }))
    .filter((row) => row.term.toLowerCase().includes(search.trim().toLowerCase()));

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'Rank', width: 80 },
    { field: 'term', headerName: 'Unmatched Query', flex: 2, minWidth: 200 },
    { field: 'count', headerName: 'Occurrences', width: 140, align: 'right', headerAlign: 'right' },
    { field: 'location', headerName: 'Location Area', flex: 1.2, minWidth: 150 },
  ];

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Search', href: ROUTES.SEARCH },
          { label: 'Quality' },
        ]}
      />
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Search Quality Analysis
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Match accuracy, relevance, and catalog-coverage gaps degrading discovery success.
        </Typography>
      </Box>

      <AdminDataGrid
        rows={rows as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={rows.length}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        searchPlaceholder="Search unmatched queries..."
        searchValue={search}
        onSearchChange={setSearch}
        onRefresh={() => refetch()}
        error={isError}
      />
    </Box>
  );
}
