'use client';

import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, Alert, LinearProgress, Tooltip } from '@mui/material';
import { useRouter } from 'next/navigation';
import { Upload, FileSpreadsheet, FileText, Store, Layers } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';
import { ImportJobItem, IMPORT_JOB_STATUSES } from '@/core/types/imports';
import {
  fileExtension,
  isJobActive,
  normalizeStatus,
  progressPercent,
  rejectedRowCount,
  sourceLabel,
  successRate,
} from '@/core/imports/jobUtils';

const SOURCE_ICONS: Record<string, React.ReactNode> = {
  EXCEL: <FileSpreadsheet size={16} color="#10B981" />,
  CSV: <FileText size={16} color="#0F52BA" />,
  POS: <Store size={16} color="#8B5CF6" />,
  BULK: <Layers size={16} color="#F59E0B" />,
};

/** Server-side source filters. */
const IMPORT_SOURCE_FILTERS = [
  { value: 'all', label: 'All Sources' },
  { value: 'EXCEL', label: 'Excel' },
  { value: 'CSV', label: 'CSV' },
  { value: 'POS', label: 'POS' },
  { value: 'BULK', label: 'Bulk' },
] as const;

const FilterChip: React.FC<{ label: string; active: boolean; onClick: () => void }> = ({ label, active, onClick }) => (
  <Box
    component="button"
    type="button"
    onClick={onClick}
    sx={{
      px: 1.5,
      py: 0.5,
      borderRadius: '20px',
      fontSize: '0.75rem',
      fontWeight: 600,
      fontFamily: 'inherit',
      cursor: 'pointer',
      border: '1px solid',
      borderColor: active ? 'primary.main' : '#CBD5E1',
      backgroundColor: active ? '#EFF6FF' : '#FFFFFF',
      color: active ? 'primary.main' : '#475569',
      '&:hover': { borderColor: 'primary.main' },
    }}
  >
    {label}
  </Box>
);

export default function ImportsPage() {
  const router = useRouter();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [sourceFilter, setSourceFilter] = useState<string>('all');
  const [statusFilter, setStatusFilter] = useState<string>('all');

  const { data, isLoading, refetch, isError } = useQuery<{ items: ImportJobItem[]; total: number }>({
    queryKey: ['admin', 'imports', paginationModel, sourceFilter, statusFilter],
    queryFn: () =>
      apiClient<{ items: ImportJobItem[]; total: number }>(API_ENDPOINTS.IMPORTS.LIST, {
        params: {
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
          ...(sourceFilter !== 'all' ? { source_type: sourceFilter } : {}),
          ...(statusFilter !== 'all' ? { status: statusFilter } : {}),
        },
      }),
    retry: false,
    // In-flight jobs change state without user action — poll while any is active.
    refetchInterval: (query) => {
      const items = query.state.data?.items as ImportJobItem[] | undefined;
      return items?.some((j) => isJobActive(j)) ? 5000 : false;
    },
  });

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'Job', width: 80 },
    {
      field: 'file_name',
      headerName: 'File',
      flex: 1.6,
      minWidth: 210,
      valueGetter: (_, row) => (row as ImportJobItem).file_name || `Import #${(row as ImportJobItem).id}`,
      renderCell: (params) => {
        const job = params.row as ImportJobItem;
        const src = sourceLabel(job);
        return (
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, minWidth: 0 }}>
            {SOURCE_ICONS[src] || <Upload size={16} color="#64748B" />}
            <Box sx={{ minWidth: 0 }}>
              <Typography variant="body2" sx={{ fontWeight: 600 }} noWrap>
                {job.file_name || `Import #${job.id}`}
              </Typography>
              <Typography variant="caption" color="text.secondary" noWrap>
                {src}
                {fileExtension(job) ? ` · .${fileExtension(job)}` : ''}
              </Typography>
            </Box>
          </Box>
        );
      },
    },
    {
      field: 'shop_name',
      headerName: 'Shop',
      flex: 1,
      minWidth: 150,
      valueGetter: (_, row) => (row as ImportJobItem).shop_name || '—',
    },
    {
      field: 'status',
      headerName: 'Status',
      width: 130,
      renderCell: (params) => <StatusBadge status={(params.value as string) || 'UPLOADED'} />,
    },
    { field: 'rows_total', headerName: 'Rows', width: 85, align: 'right', headerAlign: 'right' },
    {
      field: 'rows_processed',
      headerName: 'Progress',
      width: 165,
      sortable: false,
      renderCell: (params) => {
        const job = params.row as ImportJobItem;
        const pct = progressPercent(job);
        const rate = successRate(job);
        const barColor =
          normalizeStatus(job.status) === 'FAILED' ? 'error' : isJobActive(job) ? 'primary' : 'success';
        return (
          <Box sx={{ width: '100%' }}>
            <LinearProgress variant="determinate" value={pct} color={barColor} sx={{ height: 6, borderRadius: 3, mb: 0.5 }} />
            <Typography variant="caption" color="text.secondary">
              {pct}%{rate !== null ? ` · ${rate}% ok` : ''}
            </Typography>
          </Box>
        );
      },
    },
    {
      field: 'rejected',
      headerName: 'Rejected',
      width: 100,
      align: 'right',
      headerAlign: 'right',
      sortable: false,
      valueGetter: (_, row) => rejectedRowCount(row as ImportJobItem),
      renderCell: (params) => {
        const value = params.value as number;
        return (
          <Typography
            variant="body2"
            sx={{ fontWeight: value > 0 ? 700 : 400, color: value > 0 ? 'error.main' : 'text.primary' }}
          >
            {value}
          </Typography>
        );
      },
    },
    {
      field: 'started_at',
      headerName: 'Started',
      flex: 1.1,
      minWidth: 160,
      valueFormatter: (value) => (value ? new Date(value as string).toLocaleString() : 'N/A'),
    },
  ];

  const items = data?.items || [];
  const activeCount = items.filter((j) => isJobActive(j)).length;

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Import Center' },
        ]}
      />

      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Import Center
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Monitor Excel, CSV, POS and bulk ingestion pipelines across the platform.
        </Typography>
      </Box>

      {/* Lifecycle status filter rail — every documented status is reachable. */}
      <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap', mb: 1.5 }}>
        <FilterChip
          label="All"
          active={statusFilter === 'all'}
          onClick={() => {
            setStatusFilter('all');
            setPaginationModel((p) => ({ ...p, page: 0 }));
          }}
        />
        {IMPORT_JOB_STATUSES.map((status) => (
          <FilterChip
            key={status}
            label={status.charAt(0) + status.slice(1).toLowerCase()}
            active={statusFilter === status}
            onClick={() => {
              setStatusFilter(status);
              setPaginationModel((p) => ({ ...p, page: 0 }));
            }}
          />
        ))}
      </Box>

      <Box sx={{ display: 'flex', gap: 1, mb: 2, flexWrap: 'wrap', alignItems: 'center' }}>
        {IMPORT_SOURCE_FILTERS.map((filter) => (
          <FilterChip
            key={filter.value}
            label={filter.label}
            active={sourceFilter === filter.value}
            onClick={() => {
              setSourceFilter(filter.value);
              setPaginationModel((p) => ({ ...p, page: 0 }));
            }}
          />
        ))}
        {activeCount > 0 && (
          <Tooltip title="Jobs in flight are polled automatically every 5 seconds.">
            <Alert severity="info" sx={{ py: 0, ml: 'auto' }}>
              {activeCount} job{activeCount === 1 ? '' : 's'} in progress — auto-refreshing
            </Alert>
          </Tooltip>
        )}
      </Box>

      {isError && (
        <Alert severity="warning" sx={{ mb: 2 }}>
          The import jobs endpoint is unavailable on this backend, or you lack the inventory capability.
        </Alert>
      )}

      <AdminDataGrid
        rows={items as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? items.length}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        error={isError}
        errorMessage="Import jobs could not be loaded. The request failed — retry, and escalate if it keeps failing."
        searchPlaceholder="Search import jobs..."
        onRefresh={() => refetch()}
        onRowClick={(params) => router.push(ROUTES.IMPORT_DETAIL(params.row.id as number))}
      />
    </Box>
  );
}
