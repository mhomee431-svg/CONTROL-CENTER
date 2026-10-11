'use client';

import React, { useState } from 'react';
import { useRouter } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import {
  Box,
  Typography,
  Button,
  Chip,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Tooltip,
} from '@mui/material';
import { AlertCircle, ExternalLink, Search, PackageSearch, FileSearch } from 'lucide-react';
import { fetchList, ListResult } from '@/core/api/fetchList';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { ZeroResultRow } from '@/core/types/searchControl';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';
import { useDateRange } from '@/core/filters/DateRangeContext';
import { DateRangePicker } from '@/core/filters/DateRangePicker';

// ---------------------------------------------------------------------------
// Zero-Result Searches — the catalog-gap investigation surface.
// Show:    Query | Count | Date Range | Location | Potential Category |
//          Catalog Candidates (real token matches, never a recommendation).
// Actions: Investigate | Open Catalog | Search Review | Product Gap.
// ---------------------------------------------------------------------------

export default function ZeroResultsPage() {
  const router = useRouter();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [search, setSearch] = useState('');
  const [gapTarget, setGapTarget] = useState<ZeroResultRow | null>(null);
  const { params: dateParams } = useDateRange();

  // Server-paginated: the total is the true count of the window.
  const { data, isLoading, isError, refetch } = useQuery<ListResult<ZeroResultRow>>({
    queryKey: ['admin', 'search-control', 'zero-results', dateParams, paginationModel, search],
    queryFn: () =>
      fetchList<ZeroResultRow>(API_ENDPOINTS.SEARCH_CONTROL.ZERO_RESULTS, {
        params: {
          ...dateParams,
          search: search || undefined,
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
    retry: false,
  });

  const fmtDay = (v: string | null) => (v ? v.slice(0, 10) : '—');

  const columns: GridColDef[] = [
    {
      field: 'query',
      headerName: 'Query',
      flex: 1.5,
      minWidth: 190,
      renderCell: (params) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <AlertCircle size={16} color="#EF4444" />
          <Typography variant="body2" sx={{ fontWeight: 600 }}>
            “{params.value as string}”
          </Typography>
        </Box>
      ),
    },
    {
      field: 'count',
      headerName: 'Count',
      width: 110,
      align: 'right',
      headerAlign: 'right',
      valueFormatter: (v) => Number(v).toLocaleString(),
    },
    {
      field: 'first_seen',
      headerName: 'Date Range',
      flex: 1,
      minWidth: 180,
      valueFormatter: (_, row) => `${fmtDay(row.first_seen)} → ${fmtDay(row.last_seen)}`,
    },
    {
      field: 'location',
      headerName: 'Location',
      flex: 1,
      minWidth: 130,
      valueFormatter: (v) => v || 'Unknown',
    },
    {
      field: 'potential_category',
      headerName: 'Potential Category',
      flex: 1,
      minWidth: 160,
      // Backend token overlap only; null renders as an em dash — the console
      // never guesses a category the backend did not supply.
      valueFormatter: (v) => v || '—',
    },
    {
      field: 'candidate_products',
      headerName: 'Catalog Candidates',
      width: 180,
      align: 'right',
      headerAlign: 'right',
      renderCell: (params) => {
        const row = params.row as ZeroResultRow;
        const names = row.candidate_examples ?? [];
        return (
          <Tooltip
            title={
              names.length
                ? `Examples: ${names.join(', ')}`
                : 'No catalog product shares a token with this query.'
            }
          >
            <Chip
              size="small"
              label={`${row.candidate_products} candidate${row.candidate_products === 1 ? '' : 's'}`}
              color={row.candidate_products > 0 ? 'warning' : 'default'}
              variant="outlined"
            />
          </Tooltip>
        );
      },
    },
    {
      field: 'actions',
      headerName: 'Actions',
      width: 380,
      sortable: false,
      renderCell: (params) => {
        const row = params.row as ZeroResultRow;
        return (
          <Box sx={{ display: 'flex', gap: 0.5, alignItems: 'center', height: '100%' }}>
            <Button
              size="small"
              startIcon={<Search size={14} />}
              onClick={() => router.push(`${ROUTES.PRODUCTS}?search=${encodeURIComponent(row.query)}`)}
            >
              Investigate
            </Button>
            <Button size="small" startIcon={<ExternalLink size={14} />} onClick={() => router.push(ROUTES.PRODUCTS)}>
              Open Catalog
            </Button>
            <Button
              size="small"
              startIcon={<FileSearch size={14} />}
              onClick={() => router.push(`${ROUTES.SEARCH_QUALITY}?term=${encodeURIComponent(row.query)}`)}
            >
              Search Review
            </Button>
            <Button
              size="small"
              color="warning"
              startIcon={<PackageSearch size={14} />}
              onClick={() => setGapTarget(row)}
            >
              Product Gap
            </Button>
          </Box>
        );
      },
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
          Zero-Result Searches
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Real demand that found nothing: high-intent queries with zero local stock or catalog
          coverage. Candidates below are catalog rows sharing a token — evidence for review, not a
          recommendation.
        </Typography>
      </Box>

      <AdminDataGrid
        rows={(data?.items ?? []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        searchPlaceholder="Filter queries..."
        searchValue={search}
        onSearchChange={setSearch}
        onRefresh={() => refetch()}
        error={isError}
        errorMessage="Zero-result queries could not be loaded. Retry, and escalate if it keeps failing — inventing catalog gaps would risk incorrect onboarding decisions."
      />

      <Dialog open={gapTarget != null} onClose={() => setGapTarget(null)} maxWidth="sm" fullWidth>
        <DialogTitle>Product Gap — “{gapTarget?.query}”</DialogTitle>
        <DialogContent dividers>
          <Typography variant="body2" sx={{ mb: 1 }}>
            <strong>{gapTarget?.count?.toLocaleString()}</strong> searches
            {gapTarget?.location ? ` from ${gapTarget.location}` : ''} between{' '}
            {fmtDay(gapTarget?.first_seen ?? null)} and {fmtDay(gapTarget?.last_seen ?? null)}{' '}
            returned <strong>0 results</strong>.
          </Typography>
          <Typography variant="body2" sx={{ mb: 1 }}>
            Potential category (token overlap):{' '}
            <strong>{gapTarget?.potential_category ?? '— none matched —'}</strong>
          </Typography>
          <Typography variant="body2" sx={{ mb: 1 }}>
            Catalog candidates sharing a token ({gapTarget?.candidate_products ?? 0}):
          </Typography>
          {(gapTarget?.candidate_examples?.length ?? 0) === 0 ? (
            <Typography variant="body2" color="text.secondary">
              No catalog product shares a token with this query — the gap is at the catalog level.
            </Typography>
          ) : (
            <ul style={{ margin: 0, paddingLeft: 20 }}>
              {gapTarget!.candidate_examples.map((name) => (
                <li key={name}>
                  <Typography variant="body2">{name}</Typography>
                </li>
              ))}
            </ul>
          )}
          <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 2 }}>
            These are observed candidates only. The platform does not claim a matching product —
            the customer search itself returned nothing.
          </Typography>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setGapTarget(null)}>Close</Button>
          <Button
            variant="outlined"
            onClick={() => {
              const q = gapTarget?.query ?? '';
              setGapTarget(null);
              router.push(`${ROUTES.PRODUCTS}?search=${encodeURIComponent(q)}`);
            }}
          >
            Open in Catalog
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
