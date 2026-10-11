'use client';

import React, { useEffect, useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import {
  Box,
  Typography,
  Card,
  CardContent,
  Button,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  TextField,
  Alert,
  Divider,
  Tooltip,
} from '@mui/material';
import { Download, FileClock, Loader2, Ban } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';
import {
  ExportDatasetsResponse,
  ExportJobItem,
  ExportJobPayload,
} from '@/core/types/admin';

/** Job states that can still be cancelled or are still in flight. */
const ACTIVE_JOB_STATES: ReadonlyArray<string> = ['QUEUED', 'PROCESSING'];

/**
 * EXPORT CENTER.
 *
 * Large exports are asynchronous backend jobs, never a file assembled in the
 * browser (EXPORT CENTER rule). This page therefore does two things and no
 * more: queue a job against a named dataset, and observe the queue's real
 * state. It never displays a row count the backend has not reported.
 *
 * Jobs still in flight poll on a short interval so the operator sees progress
 * without a manual refresh; polling stops entirely when every job on the page
 * is terminal, so an idle page makes no network traffic.
 */
export default function ExportCenterPage() {
  const queryClient = useQueryClient();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [dataset, setDataset] = useState('');
  const [search, setSearch] = useState('');
  const [reason, setReason] = useState('');
  const [successMsg, setSuccessMsg] = useState<string | null>(null);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [cancelTarget, setCancelTarget] = useState<ExportJobItem | null>(null);

  const { data: datasets, isLoading: datasetsLoading } = useQuery<ExportDatasetsResponse>({
    queryKey: ['admin', 'exports', 'datasets'],
    queryFn: () => apiClient<ExportDatasetsResponse>(API_ENDPOINTS.EXPORTS.DATASETS),
    retry: false,
  });

  const { data, isLoading, isError, refetch } = useQuery<{ items: ExportJobItem[]; total: number }>({
    queryKey: ['admin', 'exports', 'jobs', paginationModel],
    queryFn: () =>
      apiClient<{ items: ExportJobItem[]; total: number }>(API_ENDPOINTS.EXPORTS.JOBS, {
        params: {
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
    retry: false,
  });

  // Real-time observation: poll while at least one job on this page is still
  // in flight. Purely client-driven; the backend remains authoritative.
  const hasActiveJobs = useMemo(
    () => (data?.items ?? []).some((job) => ACTIVE_JOB_STATES.includes(job.status)),
    [data]
  );

  useEffect(() => {
    if (!hasActiveJobs) return;
    const interval = window.setInterval(() => {
      void refetch();
    }, 5000);
    return () => window.clearInterval(interval);
  }, [hasActiveJobs, refetch]);

  const requestMutation = useMutation({
    mutationFn: (payload: ExportJobPayload) =>
      apiClient(API_ENDPOINTS.EXPORTS.JOBS, { method: 'POST', body: JSON.stringify(payload) }),
    onSuccess: () => {
      setSuccessMsg('Export queued. The server resolves it against real tables — this page reflects progress.');
      setReason('');
      queryClient.invalidateQueries({ queryKey: ['admin', 'exports', 'jobs'] });
    },
    onError: (err: unknown) => {
      setErrorMsg(err instanceof Error ? err.message : 'Failed to queue the export.');
    },
  });

  const cancelMutation = useMutation({
    mutationFn: (id: number | string) =>
      apiClient(API_ENDPOINTS.EXPORTS.JOB_CANCEL(id), { method: 'POST' }),
    onSuccess: () => {
      setCancelTarget(null);
      queryClient.invalidateQueries({ queryKey: ['admin', 'exports', 'jobs'] });
    },
    onError: (err: unknown) => {
      setErrorMsg(err instanceof Error ? err.message : 'Failed to cancel the export job.');
      setCancelTarget(null);
    },
  });

  const handleRequest = () => {
    setSuccessMsg(null);
    setErrorMsg(null);
    if (!dataset) {
      setErrorMsg('Choose a dataset to export.');
      return;
    }
    requestMutation.mutate({
      dataset,
      filters: search.trim() ? { search: search.trim() } : null,
      reason: reason.trim() || undefined,
    });
  };

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    {
      field: 'dataset',
      headerName: 'Dataset',
      flex: 1,
      minWidth: 150,
      valueFormatter: (value) => {
        const match = datasets?.items.find((d) => d.key === value);
        return match ? match.label : String(value || '');
      },
    },
    {
      field: 'status',
      headerName: 'Status',
      width: 140,
      renderCell: (params) => <StatusBadge status={(params.value as string) || 'QUEUED'} />,
    },
    {
      field: 'rows_exported',
      headerName: 'Rows',
      width: 130,
      valueGetter: (_, row) => {
        const job = row as ExportJobItem;
        // A job that has not produced a result reports no count at all.
        return job.rows_exported == null ? '—' : job.rows_exported.toLocaleString();
      },
    },
    {
      field: 'file_size_bytes',
      headerName: 'Size',
      width: 110,
      valueGetter: (_, row) => {
        const bytes = (row as ExportJobItem).file_size_bytes;
        return bytes == null ? '—' : `${(bytes / 1024).toFixed(1)} KB`;
      },
    },
    {
      field: 'requested_by',
      headerName: 'Requested By',
      flex: 1,
      minWidth: 140,
      valueGetter: (_, row) => (row as ExportJobItem).requested_by || '—',
    },
    {
      field: 'created_at',
      headerName: 'Requested',
      flex: 1.2,
      minWidth: 170,
      valueFormatter: (value) => (value ? new Date(value as string).toLocaleString() : 'N/A'),
    },
    {
      field: 'action',
      headerName: 'Action',
      width: 130,
      sortable: false,
      renderCell: (params) => {
        const job = params.row as ExportJobItem;
        if (job.status === 'COMPLETED') {
          return (
            <Tooltip title="Download the finished export file">
              <Button
                size="small"
                variant="outlined"
                startIcon={<Download size={14} />}
                aria-label={`Download export job ${job.id}`}
                href={API_ENDPOINTS.EXPORTS.JOB_DETAIL(job.id) + '/download'}
              >
                Download
              </Button>
            </Tooltip>
          );
        }
        if (!ACTIVE_JOB_STATES.includes(job.status)) return null;
        return (
          <Tooltip title="Cancel this queued export">
            <Button
              size="small"
              color="error"
              variant="outlined"
              startIcon={<Ban size={14} />}
              aria-label={`Cancel export job ${job.id}`}
              disabled={cancelMutation.isPending}
              onClick={(e) => {
                e.stopPropagation();
                setCancelTarget(job);
              }}
            >
              Cancel
            </Button>
          </Tooltip>
        );
      },
    },
  ];

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Export Center' },
        ]}
      />
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Export Center
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Queue asynchronous export jobs over Customers, Shopkeepers, Businesses, Products, Inventory, Prices, Search,
          Analytics and Audit Logs. Large exports run on the backend — files are never assembled in the browser.
        </Typography>
      </Box>

      {successMsg && (
        <Alert severity="success" sx={{ mb: 3 }} onClose={() => setSuccessMsg(null)}>
          {successMsg}
        </Alert>
      )}
      {errorMsg && (
        <Alert severity="error" sx={{ mb: 3 }} onClose={() => setErrorMsg(null)}>
          {errorMsg}
        </Alert>
      )}

      <Card sx={{ mb: 3 }}>
        <CardContent sx={{ p: 3 }}>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 2 }}>
            <FileClock size={18} color="#0F52BA" />
            <Typography variant="h6">Request an Export</Typography>
          </Box>

          <PermissionGuard capability={CAPABILITIES.EXPORTS_GENERATE}>
            <Box
              sx={{
                display: 'grid',
                gridTemplateColumns: { xs: '1fr', sm: '1fr 1fr 1fr' },
                gap: 2,
              }}
            >
              <FormControl fullWidth margin="dense">
                <InputLabel id="export-dataset-label">Dataset</InputLabel>
                <Select
                  labelId="export-dataset-label"
                  value={dataset}
                  label="Dataset"
                  onChange={(e) => setDataset(e.target.value)}
                  disabled={datasetsLoading}
                >
                  {(datasets?.items ?? []).map((d) => (
                    <MenuItem key={d.key} value={d.key}>
                      {d.label}
                    </MenuItem>
                  ))}
                </Select>
              </FormControl>

              <TextField
                fullWidth
                margin="dense"
                label="Filter (optional)"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                helperText="Narrows the scope server-side before the job runs."
              />

              <TextField
                fullWidth
                margin="dense"
                label="Reason (recorded in audit log)"
                value={reason}
                onChange={(e) => setReason(e.target.value)}
              />

              <Box sx={{ gridColumn: '1 / -1', display: 'flex', alignItems: 'center', gap: 2, flexWrap: 'wrap' }}>
                <Button
                  variant="contained"
                  startIcon={
                    requestMutation.isPending ? <Loader2 size={16} className="animate-spin" /> : <Download size={16} />
                  }
                  disabled={requestMutation.isPending || !dataset}
                  onClick={handleRequest}
                >
                  {requestMutation.isPending ? 'Queueing…' : 'Queue Export Job'}
                </Button>
                {datasets?.max_rows_per_job != null && (
                  <Typography variant="caption" color="text.secondary">
                    Limit: {datasets.max_rows_per_job.toLocaleString()} rows per job.
                  </Typography>
                )}
              </Box>
            </Box>
          </PermissionGuard>
        </CardContent>
      </Card>

      <Divider sx={{ mb: 3 }} />

      <Typography variant="h6" sx={{ mb: 2 }}>
        Export Jobs
      </Typography>

      <AdminDataGrid
        rows={(data?.items || []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        error={isError}
        errorMessage="Export jobs could not be loaded. The request failed — retry, and escalate if it keeps failing."
        searchPlaceholder="Search export jobs..."
        onRefresh={() => refetch()}
      />

      <ConfirmationDialog
        open={Boolean(cancelTarget)}
        title={`Cancel export job #${cancelTarget?.id ?? ''}`}
        affectedItem={
          cancelTarget ? `${cancelTarget.dataset} · queued by ${cancelTarget.requested_by || 'unknown'}` : undefined
        }
        actionSummary="Action: CANCEL EXPORT JOB"
        consequence="This queued export will not run; the job is marked CANCELLED."
        isDangerous={false}
        requireReason
        isLoading={cancelMutation.isPending}
        onConfirm={async () => {
          if (!cancelTarget) return;
          await cancelMutation.mutateAsync(cancelTarget.id);
        }}
        onClose={() => setCancelTarget(null)}
      />
    </Box>
  );
}
