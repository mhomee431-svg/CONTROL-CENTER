'use client';

import React, { useState } from 'react';
import { useRouter } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, Button, Alert } from '@mui/material';
import { AlertCircle, ExternalLink } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AnalyticsSummary } from '@/core/types/analytics';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';
import { useDateRange } from '@/core/filters/DateRangeContext';
import { DateRangePicker } from '@/core/filters/DateRangePicker';

/**
 * Documented sample shape retained as a TYPE reference only.
 *
 * These are deliberately NOT used as runtime data: the page must never render
 * invented catalog gaps, because an operator could act on them (onboarding a
 * merchant for a product that was never actually searched for). When the
 * analytics endpoint is unreachable the grid renders empty with an explicit
 * error, which is the only honest state.
 */
export type ZeroResultItem = {
  id: number;
  query: string;
  search_count: number;
  location: string;
  potential_category: string;
  last_searched: string;
};

export default function ZeroResultsPage() {
  const router = useRouter();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });

  const { params: dateParams } = useDateRange();

  const { data, isLoading, isError, refetch } = useQuery<AnalyticsSummary>({
    queryKey: ['admin', 'analytics', 'summary', dateParams],
    queryFn: () =>
      apiClient<AnalyticsSummary>(API_ENDPOINTS.DASHBOARD.ANALYTICS_SUMMARY, {
        params: dateParams,
      }),
    retry: false,
  });

  // Real backend zero-result queries, mapped into the grid row contract.
  const rows: ZeroResultItem[] = (data?.zero_result_queries ?? []).map((q, idx) => ({
    id: idx + 1,
    query: q.query,
    search_count: q.count,
    location: q.location || 'Unknown',
    potential_category: '—',
    last_searched: new Date().toISOString(),
  }));

  // An empty-but-successful response means "no gaps", which is a real finding.
  // An error means "unknown", which is reported as an error — never as data.

  const reviewGap = (query: string) =>
    router.push(`${ROUTES.PRODUCTS}?search=${encodeURIComponent(query)}`);

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 70 },
    {
      field: 'query',
      headerName: 'Searched Term',
      flex: 1.5,
      minWidth: 180,
      renderCell: (params) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <AlertCircle size={16} color="#EF4444" />
          <Typography variant="body2" sx={{ fontWeight: 600 }}>
            &quot;{params.value as string}&quot;
          </Typography>
        </Box>
      ),
    },
    {
      field: 'search_count',
      headerName: 'Search Volume (0 Results)',
      width: 220,
      align: 'right',
      headerAlign: 'right',
      valueFormatter: (value) => `${Number(value).toLocaleString()} queries`,
    },
    { field: 'location', headerName: 'Shopper Location Area', flex: 1.2, minWidth: 160 },
    { field: 'potential_category', headerName: 'Likely Taxonomy', flex: 1, minWidth: 140 },
    {
      field: 'actions',
      headerName: 'Operational Actions',
      width: 200,
      sortable: false,
      renderCell: (params) => (
        <Button
          size="small"
          variant="outlined"
          startIcon={<ExternalLink size={14} />}
          onClick={() => reviewGap(String(params.row.query ?? ''))}
        >
          Review Catalog Gap
        </Button>
      ),
    },
  ];

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Search', href: ROUTES.SEARCH },
          { label: 'Zero Results' },
        ]}
      />
      <DateRangePicker />

      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Zero-Result Search Analysis
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Section 42: High customer demand with zero local stock. Identify merchant onboarding gaps and catalog deficiencies.
        </Typography>
      </Box>

      {isError ? (
        <Alert severity="error" sx={{ mb: 2 }}>
          Analytics endpoint is unavailable — zero-result queries could not be loaded. No data is
          shown because inventing catalog gaps would risk incorrect merchant onboarding decisions.
        </Alert>
      ) : (
        <Alert severity="info" sx={{ mb: 2 }}>
          These queries returned 0 nearby shops. Review these gaps to onboard target merchants or expand the canonical catalog.
        </Alert>
      )}

      <AdminDataGrid
        rows={rows as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={rows.length}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        onRefresh={() => refetch()}
        onRowClick={(params) => reviewGap(String(params.row.query ?? ''))}
      />
    </Box>
  );
}
