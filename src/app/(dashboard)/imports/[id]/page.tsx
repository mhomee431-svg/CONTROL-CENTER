'use client';

import React, { useState } from 'react';
import { useRouter } from 'next/navigation';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  Box,
  Card,
  CardContent,
  Button,
  Typography,
  Alert,
  Grid,
  Divider,
  Chip,
  CircularProgress,
  LinearProgress,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
} from '@mui/material';
import {
  ArrowLeft,
  Upload,
  Download,
  RotateCcw,
  Ban,
  AlertTriangle,
  CheckCircle2,
  XCircle,
  Copy,
  Timer,
} from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';
import { StatusBadge } from '@/core/components/StatusBadge';
import { ROUTES } from '@/core/routes/routes';
import { ImportJobItem, ImportRowError } from '@/core/types/imports';
import {
  canCancelJob,
  canDownloadReport,
  canRetryJob,
  fileExtension,
  formatBytes,
  formatDuration,
  ingestedRowCount,
  isJobActive,
  normalizeStatus,
  progressPercent,
  rejectedRowCount,
  sourceLabel,
  successRate,
  validateReportUrl,
} from '@/core/imports/jobUtils';

export default function ImportDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = React.use(params);
  const router = useRouter();
  const queryClient = useQueryClient();

  const [actionError, setActionError] = useState<string | null>(null);
  const [pendingAction, setPendingAction] = useState<'RETRY' | 'CANCEL' | null>(null);
  const [showErrors, setShowErrors] = useState(false);

  const { data: job, isLoading, isError } = useQuery<ImportJobItem>({
    queryKey: ['admin', 'import', id],
    queryFn: () => apiClient<ImportJobItem>(API_ENDPOINTS.IMPORTS.DETAIL(id)),
    retry: false,
    refetchInterval: (query) => {
      const current = query.state.data as ImportJobItem | undefined;
      return current && isJobActive(current) ? 5000 : false;
    },
  });

  const { data: errors, isLoading: errorsLoading } = useQuery<{ items: ImportRowError[]; total?: number }>({
    queryKey: ['admin', 'import-errors', id],
    queryFn: () => apiClient<{ items: ImportRowError[]; total?: number }>(API_ENDPOINTS.IMPORTS.ERRORS(id)),
    enabled: showErrors,
    retry: false,
  });

  const invalidate = () => {
    queryClient.invalidateQueries({ queryKey: ['admin', 'import', id] });
    queryClient.invalidateQueries({ queryKey: ['admin', 'imports'] });
  };

  const retryMutation = useMutation({
    mutationFn: (reason: string) =>
      apiClient(API_ENDPOINTS.IMPORTS.RETRY(id), {
        method: 'POST',
        body: JSON.stringify({ reason }),
      }),
    onSuccess: () => {
      setPendingAction(null);
      setActionError(null);
      invalidate();
    },
    onError: (err: unknown) => setActionError(err instanceof Error ? err.message : 'Retry failed.'),
  });

  const cancelMutation = useMutation({
    mutationFn: (reason: string) =>
      apiClient(API_ENDPOINTS.IMPORTS.CANCEL(id), {
        method: 'POST',
        body: JSON.stringify({ reason }),
      }),
    onSuccess: () => {
      setPendingAction(null);
      setActionError(null);
      invalidate();
    },
    onError: (err: unknown) => setActionError(err instanceof Error ? err.message : 'Cancel failed.'),
  });

  const reportCheck = job ? validateReportUrl(job.report_url) : { valid: false, reason: 'No report available.' };
  const status = job ? normalizeStatus(job.status) : 'UNKNOWN';
  const rejected = rejectedRowCount(job);
  const duration = job ? formatDuration(job) : null;

  const handleDownload = () => {
    if (!reportCheck.valid || !reportCheck.url) return;
    // Open via the validated relative path only.
    window.open(reportCheck.url, '_blank', 'noopener,noreferrer');
  };

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Import Center', href: ROUTES.IMPORTS },
          { label: job?.file_name || `Job #${id}` },
        ]}
      />
      <Button startIcon={<ArrowLeft size={16} />} onClick={() => router.push(ROUTES.IMPORTS)} sx={{ mb: 2 }}>
        Back to Import Center
      </Button>

      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      )}

      {isError && (
        <Alert severity="error" sx={{ mb: 2 }}>
          Could not load import job #{id}. The ingestion endpoint may not be available on this backend.
        </Alert>
      )}

      {actionError && (
        <Alert severity="error" sx={{ mb: 2 }} onClose={() => setActionError(null)}>
          {actionError}
        </Alert>
      )}

      {!isLoading && job && (
        <>
          <Card sx={{ mb: 2 }}>
            <CardContent sx={{ p: 3 }}>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2, flexWrap: 'wrap', gap: 2 }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                  <Box sx={{ p: 1.2, borderRadius: 2, backgroundColor: '#EFF6FF', color: 'primary.main' }}>
                    <Upload size={24} />
                  </Box>
                  <Box>
                    <Typography variant="h6" sx={{ fontWeight: 700 }}>
                      {job.file_name || `Import Job #${job.id}`}
                    </Typography>
                    <Typography variant="body2" color="text.secondary">
                      {sourceLabel(job)} source
                      {fileExtension(job) ? ` · .${fileExtension(job)}` : ''}
                      {job.file_size_bytes ? ` · ${formatBytes(job.file_size_bytes)}` : ''}
                    </Typography>
                  </Box>
                </Box>
                <StatusBadge status={job.status || 'UPLOADED'} size="medium" />
              </Box>

              {/* Progress */}
              <Box sx={{ mb: 1 }}>
                <LinearProgress
                  variant="determinate"
                  value={progressPercent(job)}
                  color={status === 'FAILED' ? 'error' : isJobActive(job) ? 'primary' : 'success'}
                  sx={{ height: 10, borderRadius: 5 }}
                />
                <Box sx={{ display: 'flex', justifyContent: 'space-between', mt: 0.5 }}>
                  <Typography variant="caption" color="text.secondary">
                    {ingestedRowCount(job)} of {job.rows_total ?? 0} rows ingested
                  </Typography>
                  <Typography variant="caption" color="text.secondary">
                    {successRate(job) !== null ? `${successRate(job)}% success rate` : 'No rows attempted'}
                  </Typography>
                </Box>
              </Box>

              {job.error_message && (
                <Alert severity={status === 'PARTIAL' ? 'warning' : 'error'} sx={{ mt: 2 }}>
                  <strong>{status === 'PARTIAL' ? 'Completed with errors: ' : 'Import failed: '}</strong>
                  {job.error_message}
                </Alert>
              )}

              {/* Row accounting */}
              <Divider sx={{ my: 2 }} />
              <Typography variant="caption" sx={{ fontWeight: 700, color: '#64748B', letterSpacing: '0.04em' }}>
                ROW ACCOUNTING
              </Typography>
              <Grid container spacing={2} sx={{ mt: 0.5 }}>
                <Grid item xs={6} sm={3}>
                  <StatTile label="Rows" value={job.rows_total ?? 0} icon={<Copy size={15} />} />
                </Grid>
                <Grid item xs={6} sm={3}>
                  <StatTile label="Valid" value={job.rows_valid ?? 0} color="#10B981" icon={<CheckCircle2 size={15} />} />
                </Grid>
                <Grid item xs={6} sm={3}>
                  <StatTile label="Invalid" value={job.rows_invalid ?? 0} color="#EF4444" icon={<XCircle size={15} />} />
                </Grid>
                <Grid item xs={6} sm={3}>
                  <StatTile
                    label="Duplicates"
                    value={job.rows_duplicate ?? 0}
                    color="#F59E0B"
                    icon={<Copy size={15} />}
                  />
                </Grid>
                <Grid item xs={6} sm={3}>
                  <StatTile label="Processed" value={job.rows_processed ?? 0} color="#0F52BA" icon={<CheckCircle2 size={15} />} />
                </Grid>
                <Grid item xs={6} sm={3}>
                  <StatTile label="Failed" value={job.rows_failed ?? 0} color="#EF4444" icon={<XCircle size={15} />} />
                </Grid>
                <Grid item xs={6} sm={3}>
                  <StatTile label="Rejected (total)" value={rejected} color="#EF4444" icon={<AlertTriangle size={15} />} />
                </Grid>
                <Grid item xs={6} sm={3}>
                  <StatTile
                    label="Duration"
                    value={duration || (isJobActive(job) ? 'Running' : 'N/A')}
                    icon={<Timer size={15} />}
                  />
                </Grid>
              </Grid>

              <Divider sx={{ my: 2 }} />
              <Grid container spacing={2}>
                <Grid item xs={12} sm={6}>
                  <Typography variant="caption" color="text.secondary">
                    Shop
                  </Typography>
                  <Typography variant="body2" sx={{ fontWeight: 600 }}>
                    {job.shop_name || (job.shop_id ? `Shop #${job.shop_id}` : 'Platform-wide')}
                  </Typography>
                </Grid>
                <Grid item xs={12} sm={6}>
                  <Typography variant="caption" color="text.secondary">
                    Uploaded By
                  </Typography>
                  <Typography variant="body2" sx={{ fontWeight: 600 }}>
                    {job.uploaded_by || 'System'}
                  </Typography>
                </Grid>
                <Grid item xs={12} sm={6}>
                  <Typography variant="caption" color="text.secondary">
                    Started
                  </Typography>
                  <Typography variant="body2" sx={{ fontWeight: 600 }}>
                    {job.started_at ? new Date(job.started_at).toLocaleString() : 'Not started'}
                  </Typography>
                </Grid>
                <Grid item xs={12} sm={6}>
                  <Typography variant="caption" color="text.secondary">
                    Finished
                  </Typography>
                  <Typography variant="body2" sx={{ fontWeight: 600 }}>
                    {job.finished_at ? new Date(job.finished_at).toLocaleString() : 'In progress'}
                  </Typography>
                </Grid>
              </Grid>
            </CardContent>
          </Card>

          {/* Actions */}
          <Card sx={{ mb: 2 }}>
            <CardContent sx={{ p: 2.5 }}>
              <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 1.5 }}>
                Actions
              </Typography>
              <Box sx={{ display: 'flex', gap: 1.5, flexWrap: 'wrap' }}>
                <PermissionGuard capability={CAPABILITIES.INVENTORY_READ}>
                  <Button
                    variant="outlined"
                    startIcon={<AlertTriangle size={15} />}
                    onClick={() => setShowErrors((v) => !v)}
                    disabled={rejected === 0 && !job.error_message}
                  >
                    {showErrors ? 'Hide Errors' : 'View Errors'}
                  </Button>
                </PermissionGuard>

                {/* Download Report — only when the backend produced one. */}
                {canDownloadReport(job) && (
                  <PermissionGuard capability={CAPABILITIES.INVENTORY_READ}>
                    <Button
                      variant="outlined"
                      startIcon={<Download size={15} />}
                      onClick={handleDownload}
                      disabled={!reportCheck.valid}
                    >
                      Download Report
                    </Button>
                  </PermissionGuard>
                )}
                {!reportCheck.valid && reportCheck.reason && status !== 'UPLOADED' && (
                  <Typography variant="caption" color="text.secondary" sx={{ alignSelf: 'center' }}>
                    {reportCheck.reason}
                  </Typography>
                )}

                {/* Retry — only for PARTIAL / FAILED, and only when supported. */}
                {canRetryJob(job) && (
                  <PermissionGuard capability={CAPABILITIES.INVENTORY_UPDATE}>
                    <Button
                      variant="contained"
                      color="warning"
                      startIcon={<RotateCcw size={15} />}
                      onClick={() => setPendingAction('RETRY')}
                    >
                      Retry Failed Rows
                    </Button>
                  </PermissionGuard>
                )}

                {/* Cancel — only while in flight. */}
                {canCancelJob(job) && (
                  <PermissionGuard capability={CAPABILITIES.INVENTORY_UPDATE}>
                    <Button
                      variant="outlined"
                      color="error"
                      startIcon={<Ban size={15} />}
                      onClick={() => setPendingAction('CANCEL')}
                    >
                      Cancel Job
                    </Button>
                  </PermissionGuard>
                )}
              </Box>
            </CardContent>
          </Card>

          {/* Row-level errors */}
          {showErrors && (
            <Card>
              <CardContent sx={{ p: 3 }}>
                <Typography variant="h6" sx={{ fontWeight: 700, mb: 2 }}>
                  Row-Level Errors
                </Typography>

                {errorsLoading && (
                  <Box sx={{ display: 'flex', justifyContent: 'center', py: 3 }}>
                    <CircularProgress size={24} />
                  </Box>
                )}

                {!errorsLoading && errors?.items?.length === 0 && (
                  <Alert severity="success">No row-level errors were recorded for this job.</Alert>
                )}

                {!errorsLoading && errors?.items && errors.items.length > 0 && (
                  <Paper variant="outlined" sx={{ overflow: 'auto' }}>
                    <Table size="small">
                      <TableHead>
                        <TableRow sx={{ backgroundColor: '#F8FAFC' }}>
                          <TableCell sx={{ fontWeight: 700 }}>Row</TableCell>
                          <TableCell sx={{ fontWeight: 700 }}>Field</TableCell>
                          <TableCell sx={{ fontWeight: 700 }}>Reason</TableCell>
                          <TableCell sx={{ fontWeight: 700 }}>Value</TableCell>
                          <TableCell sx={{ fontWeight: 700 }}>Severity</TableCell>
                        </TableRow>
                      </TableHead>
                      <TableBody>
                        {errors.items.map((rowError, idx) => (
                          <TableCellRow key={rowError.id ?? idx} rowError={rowError} />
                        ))}
                      </TableBody>
                    </Table>
                  </Paper>
                )}

                {!errorsLoading && !errors && (
                  <Alert severity="warning">
                    Row-level error detail is unavailable for this job on the current backend.
                  </Alert>
                )}
              </CardContent>
            </Card>
          )}
        </>
      )}

      {/* Confirmation dialogs for destructive/repeatable operations */}
      <ConfirmationDialog
        open={pendingAction === 'RETRY'}
        title="Retry Failed Import Rows"
        affectedItem={job?.file_name || `Job #${id}`}
        consequence="This re-submits the rejected rows for processing. Rows that already succeeded will not be duplicated."
        isLoading={retryMutation.isPending}
        onConfirm={async (reason) => {
          await retryMutation.mutateAsync(reason);
        }}
        onClose={() => setPendingAction(null)}
      />

      <ConfirmationDialog
        open={pendingAction === 'CANCEL'}
        title="Cancel Import Job"
        affectedItem={job?.file_name || `Job #${id}`}
        consequence="This aborts the running ingestion job. Rows already ingested will remain, and the job cannot be resumed."
        isDangerous
        isLoading={cancelMutation.isPending}
        onConfirm={async (reason) => {
          await cancelMutation.mutateAsync(reason);
        }}
        onClose={() => setPendingAction(null)}
      />
    </Box>
  );
}

const StatTile: React.FC<{ label: string; value: number | string; color?: string; icon?: React.ReactNode }> = ({
  label,
  value,
  color = '#64748B',
  icon,
}) => (
  <Box
    sx={{
      p: 1.5,
      borderRadius: 1.5,
      border: '1px solid #E2E8F0',
      backgroundColor: '#F8FAFC',
    }}
  >
    <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, mb: 0.5 }}>
      <Box sx={{ color }}>{icon}</Box>
      <Typography variant="caption" color="text.secondary">
        {label}
      </Typography>
    </Box>
    <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>
      {value}
    </Typography>
  </Box>
);

const TableCellRow: React.FC<{ rowError: ImportRowError }> = ({ rowError }) => (
  <TableRow>
    <TableCell>{rowError.row_number ?? '—'}</TableCell>
    <TableCell>{rowError.field || '—'}</TableCell>
    <TableCell>{rowError.error || '—'}</TableCell>
    <TableCell sx={{ maxWidth: 220, overflow: 'hidden', textOverflow: 'ellipsis' }}>{rowError.value || '—'}</TableCell>
    <TableCell>
      <Chip
        size="small"
        label={(rowError.severity || 'ERROR').toUpperCase()}
        color={(rowError.severity || 'ERROR').toUpperCase() === 'WARNING' ? 'warning' : 'error'}
        variant="outlined"
      />
    </TableCell>
  </TableRow>
);
