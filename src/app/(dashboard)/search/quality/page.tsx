'use client';

import React, { useState } from 'react';
import { useSearchParams } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, Grid, Card, CardContent, Alert, Chip } from '@mui/material';
import { fetchList, ListResult } from '@/core/api/fetchList';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { SearchControlSummary, SearchQualityRow } from '@/core/types/searchControl';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';
import { useDateRange } from '@/core/filters/DateRangeContext';
import { DateRangePicker } from '@/core/filters/DateRangePicker';
import { apiClient } from '@/core/api/client';

// ---------------------------------------------------------------------------
// Search Quality — the Search Review surface.
// Monitor: success rate, zero-result rate, avg result count, per-term
//          breakdown. Click rate, matching rates and latency are not
//          collected by the platform and render "Not collected" — never a
//          fabricated zero. Matching diagnostics (exact/fuzzy/relevance) are
//          likewise not collected; no search-engine logic runs here.
// ---------------------------------------------------------------------------

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <Grid item xs={12} sm={6} md={3}>
      <Card sx={{ height: '100%' }}>
        <CardContent sx={{ p: 2.5 }}>
          <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 600 }}>
            {label}
          </Typography>
          <Typography variant="h5" sx={{ fontWeight: 800, mt: 0.5 }}>
            {value}
          </Typography>
        </CardContent>
      </Card>
    </Grid>
  );
}

export default function SearchQualityPage() {
  const searchParams = useSearchParams();
  return (
    <React.Suspense fallback={null}>
      <SearchQualityContent initialTerm={searchParams.get('term') ?? ''} />
    </React.Suspense>
  );
}

function SearchQualityContent({ initialTerm }: { initialTerm: string }) {
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  // Deep link: the zero-results page's "Search Review" lands on ?term=<query>.
  const [term, setTerm] = useState(initialTerm);

  const { params: dateParams } = useDateRange();

  const { data: summary, isError: summaryError } = useQuery<SearchControlSummary>({
    queryKey: ['admin', 'search-control', 'summary', dateParams],
    queryFn: () =>
      apiClient<SearchControlSummary>(API_ENDPOINTS.SEARCH_CONTROL.SUMMARY, { params: dateParams }),
    retry: false,
  });

  const { data, isLoading, isError, refetch } = useQuery<ListResult<SearchQualityRow>>({
    queryKey: ['admin', 'search-control', 'quality', dateParams, paginationModel, term],
    queryFn: () =>
      fetchList<SearchQualityRow>(API_ENDPOINTS.SEARCH_CONTROL.QUALITY, {
        params: {
          ...dateParams,
          search: term || undefined,
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
    retry: false,
  });

  const quality = summary?.quality;
  const fmt = (v: number | null | undefined, suffix = '') => (v != null ? `${v}${suffix}` : '—');

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'Rank', width: 80 },
    { field: 'term', headerName: 'Search Term', flex: 2, minWidth: 200 },
    { field: 'searches', headerName: 'Searches', width: 110, align: 'right', headerAlign: 'right' },
    { field: 'zero_count', headerName: 'Zero Results', width: 130, align: 'right', headerAlign: 'right' },
    {
      field: 'zero_rate',
      headerName: 'Zero Rate',
      width: 120,
      align: 'right',
      headerAlign: 'right',
      valueFormatter: (v) => (v != null ? `${v}%` : '—'),
    },
    {
      field: 'success_rate',
      headerName: 'Success Rate',
      width: 140,
      align: 'right',
      headerAlign: 'right',
      valueFormatter: (v) => (v != null ? `${v}%` : '—'),
    },
    {
      field: 'avg_result_count',
      headerName: 'Avg Results',
      width: 130,
      align: 'right',
      headerAlign: 'right',
      valueFormatter: (v) => (v != null ? String(v) : '—'),
    },
    {
      field: 'first_seen',
      headerName: 'Seen',
      flex: 1,
      minWidth: 170,
      valueFormatter: (_, row) => {
        const d = (v: string | null) => (v ? v.slice(0, 10) : '—');
        return `${d(row.first_seen)} → ${d(row.last_seen)}`;
      },
    },
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
      <DateRangePicker />

      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Search Quality
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Per-term success and zero-result rates from recorded searches. Matching diagnostics and
          latency are not collected — no search-engine logic runs in this console.
        </Typography>
      </Box>

      <Grid container spacing={2.5} sx={{ mb: 2 }}>
        <Metric label="SEARCH SUCCESS" value={fmt(quality?.success_rate, '%')} />
        <Metric label="ZERO-RESULT RATE" value={fmt(quality?.zero_result_rate, '%')} />
        <Metric label="AVG RESULT COUNT" value={fmt(quality?.avg_result_count)} />
        <Metric label="CLICK RATE" value="Not collected" />
        <Metric label="PRODUCT MATCHING" value={fmt(quality?.product_matching_rate, '%') === '—' ? 'Not collected' : fmt(quality?.product_matching_rate, '%')} />
        <Metric label="SHOP MATCHING" value={fmt(quality?.shop_matching_rate, '%') === '—' ? 'Not collected' : fmt(quality?.shop_matching_rate, '%')} />
        <Metric label="LATENCY" value="Not collected" />
        <Metric label="SEARCH FAILURES" value="Not collected" />
      </Grid>

      {(summaryError || isError) && (
        <Alert severity="error" sx={{ mb: 2 }}>
          Search quality data could not be loaded. Retry before drawing any conclusion about
          relevance or coverage.
        </Alert>
      )}
      {!summaryError && (
        <Alert severity="info" sx={{ mb: 2 }}>
          {summary?.diagnostics?.note ?? 'Matching diagnostics (exact, fuzzy, relevance) are not collected by this platform.'}
        </Alert>
      )}

      <AdminDataGrid
        rows={(data?.items ?? []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        searchPlaceholder="Review a term..."
        searchValue={term}
        onSearchChange={setTerm}
        onRefresh={() => refetch()}
        error={isError}
        errorMessage="Per-term quality data could not be loaded. Retry, and escalate if it keeps failing."
      />
    </Box>
  );
}
