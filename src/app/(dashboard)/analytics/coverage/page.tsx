'use client';

import React from 'react';
import { useSearchParams, useRouter } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import {
  Box,
  Typography,
  Card,
  CardContent,
  Alert,
  CircularProgress,
  Chip,
  Button,
} from '@mui/material';
import {
  Store,
  AlertCircle,
  ArrowRight,
  Info,
} from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { CoverageAnalysisItem, CoverageGap } from '@/core/types/analytics';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';
import { useDateRange } from '@/core/filters/DateRangeContext';
import { toFilterParams } from '@/core/filters/dashboardFilters';

// ---------------------------------------------------------------------------
// Coverage Analysis — high demand / low shop coverage.
// ---------------------------------------------------------------------------
// Where customer demand and recorded search traffic outrun live shopfronts, an
// admin should be able to see it at a glance. This page is analytics only: every
// figure is a server-side count of real registered users, real shops and real
// searches in the selected window. `coverage_gap` is a purely arithmetic tag
// over those three counts.

interface CoverageContentProps {
  initialCity?: string;
  initialStatus?: string;
}

function coverageLabel(gap: CoverageGap): {
  label: string;
  color: React.ComponentProps<typeof Chip>['color'];
  icon: React.ReactElement;
} {
  switch (gap) {
    case 'HIGH_DEMAND_LOW_COVERAGE':
      return { label: 'High demand, low coverage', color: 'warning', icon: <AlertCircle size={14} /> };
    case 'NO_SHOPS':
      return { label: 'No shops yet', color: 'error', icon: <Store size={14} /> };
    case 'BALANCED':
      return { label: 'Balanced', color: 'success', icon: <Store size={14} /> };
    case 'NO_DATA':
      return { label: 'No data', color: 'default', icon: <Info size={14} /> };
  }
}

function CoverageContent({ initialCity = '', initialStatus = '' }: CoverageContentProps) {
  const searchParams = useSearchParams();
  const router = useRouter();
  const { params: dateParams } = useDateRange();

  const [paginationModel, setPaginationModel] = React.useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [city, setCity] = React.useState(initialCity);
  const [shopStatus, setShopStatus] = React.useState(initialStatus);

  const activeFilters = toFilterParams({ date_range: dateParams.days, city, shop_status: shopStatus });

  const { data, isLoading, isError, refetch } = useQuery<{
    items: CoverageAnalysisItem[];
    period_days: number;
    window_start: string;
    window_end: string;
  }>({
    queryKey: ['admin', 'analytics', 'coverage', { page: paginationModel.page, pageSize: paginationModel.pageSize, ...dateParams, city, shop_status: shopStatus }],
    queryFn: () =>
      apiClient<{
        items: CoverageAnalysisItem[];
        period_days: number;
        window_start: string;
        window_end: string;
      }>(API_ENDPOINTS.ANALYTICS.COVERAGE, {
        params: {
          ...dateParams,
          city: city || undefined,
          shop_status: shopStatus || undefined,
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
    retry: false,
  });

  const columns: GridColDef[] = [
    {
      field: 'city',
      headerName: 'Area',
      flex: 2.5,
      minWidth: 240,
      renderCell: (params) => {
        const row = params.row as CoverageAnalysisItem;
        return (
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, width: '100%' }}>
            <Store size={16} color="#0F52BA" />
            <Typography variant="body2" sx={{ fontWeight: 600 }}>
              {row.city}
            </Typography>
            {row.shops === 0 && row.customers > 0 && (
              <Chip size="small" label="No shops" color="error" variant="outlined" />
            )}
          </Box>
        );
      },
    },
    {
      field: 'customers',
      headerName: 'Customers',
      width: 130,
      align: 'right',
      headerAlign: 'right',
      valueFormatter: (v) => Number(v).toLocaleString(),
    },
    {
      field: 'searches',
      headerName: 'Searches',
      width: 120,
      align: 'right',
      headerAlign: 'right',
      valueFormatter: (v) => Number(v).toLocaleString(),
    },
    {
      field: 'shops',
      headerName: 'Matching Shops',
      width: 140,
      align: 'right',
      headerAlign: 'right',
      valueFormatter: (v) => Number(v).toLocaleString(),
    },
    {
      field: 'demand_per_shop',
      headerName: 'Demand / Shop',
      width: 120,
      align: 'right',
      headerAlign: 'right',
      valueFormatter: (v) => (v == null ? '—' : Number(v).toFixed(2) + ' / shop'),
    },
    {
      field: 'coverage_gap',
      headerName: 'Coverage Signal',
      width: 230,
      sortable: false,
      renderCell: (params) => {
        const row = params.row as CoverageAnalysisItem;
        const { label, color, icon } = coverageLabel(row.coverage_gap);
        return (
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, width: '100%' }}>
            {icon}
            <Chip
              size="small"
              label={label}
              color={color}
              variant={color === 'default' ? 'outlined' : 'filled'}
              sx={{ fontWeight: 600, textTransform: 'none' }}
            />
          </Box>
        );
      },
    },
    {
      field: 'action',
      headerName: 'Review',
      width: 140,
      sortable: false,
      renderCell: (params) => {
        const row = params.row as CoverageAnalysisItem;
        return (
          <Button
            size="small"
            startIcon={<ArrowRight size={14} />}
            onClick={() => router.push(`${ROUTES.LOCATIONS}?city=${encodeURIComponent(row.city)}`)}
            title="Investigate this area on the Locations registry"
          >
            Investigate
          </Button>
        );
      },
    },
  ];

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Analytics', href: ROUTES.ANALYTICS },
          { label: 'Coverage' },
        ]}
      />
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Coverage Analysis
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Where customer demand and recorded search traffic outrun live shopfronts, from server-side counts over the
          selected window.
        </Typography>
      </Box>

      {isError && (
        <Alert severity="error" sx={{ mb: 2 }}>
          Coverage data could not be loaded. The request failed — retry, and escalate if it keeps failing.
        </Alert>
      )}

      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      )}

      {!isLoading && (
        <Card>
          <CardContent sx={{ p: 2 }}>
            <AdminDataGrid
              rows={(data?.items || []) as unknown as Record<string, unknown>[]}
              columns={columns}
              totalRows={data?.items?.length ?? 0}
              paginationModel={paginationModel}
              onPaginationModelChange={setPaginationModel}
              loading={isLoading}
              error={isError}
              errorMessage="Coverage analysis could not be loaded."
              searchPlaceholder={activeFilters.city ? `City: ${activeFilters.city}` : 'Coverage by area'}
              onRefresh={() => refetch()}
            />
          </CardContent>
        </Card>
      )}
    </Box>
  );
}

export default function AnalyticsCoveragePage() {
  return (
    <React.Suspense
      fallback={
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      }
    >
      <CoverageContent />
    </React.Suspense>
  );
}
