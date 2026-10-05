'use client';

import React, { use } from 'react';
import { useRouter } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import {
  Box,
  Card,
  CardContent,
  Button,
  Typography,
  Alert,
  CircularProgress,
  Divider,
  Grid,
  LinearProgress,
} from '@mui/material';
import { ArrowLeft, Upload } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';

interface ImportJob {
  id: number;
  source?: string;
  status?: string;
  rows_total?: number;
  rows_processed?: number;
  created_at?: string;
  updated_at?: string;
  error?: string | null;
}

export default function ImportDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const router = useRouter();

  // Row-level detail is resolved from the ingestion registry so the drill-down
  // shows the real job instead of an empty shell.
  const { data, isLoading, isError } = useQuery<{ items: ImportJob[] }>({
    queryKey: ['admin', 'imports', 'detail', id],
    queryFn: () =>
      apiClient<{ items: ImportJob[] }>(API_ENDPOINTS.SYSTEM.REPORTS, { params: { limit: 250 } }),
  });

  const job = data?.items?.find((j) => String(j.id) === String(id));
  const totalRows = job?.rows_total ?? 0;
  const processed = job?.rows_processed ?? 0;
  const progress = totalRows > 0 ? Math.min(100, Math.round((processed / totalRows) * 100)) : 0;

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Imports', href: ROUTES.IMPORTS },
          { label: `Job #${id}` },
        ]}
      />
      <Button startIcon={<ArrowLeft size={16} />} onClick={() => router.push(ROUTES.IMPORTS)} sx={{ mb: 2 }}>
        Back to Imports
      </Button>

      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      )}
      {isError && <Alert severity="error">Could not load import job #{id}.</Alert>}
      {!isLoading && !isError && !job && (
        <Alert severity="warning">Import job #{id} was not found in the ingestion registry.</Alert>
      )}

      {job && (
        <Card>
          <CardContent sx={{ p: 3 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2 }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                <Box sx={{ p: 1.2, borderRadius: 2, backgroundColor: '#EFF6FF', color: 'primary.main' }}>
                  <Upload size={24} />
                </Box>
                <Box>
                  <Typography variant="h6" sx={{ fontWeight: 700 }}>
                    {job.source ? `Import: ${job.source}` : `Import Job #${job.id}`}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    Job #{job.id}
                  </Typography>
                </Box>
              </Box>
              <StatusBadge status={job.status || 'QUEUED'} size="medium" />
            </Box>

            <Divider sx={{ my: 2 }} />

            {/* Ingestion progress */}
            <Box sx={{ mb: 2 }}>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 0.5 }}>
                <Typography variant="caption" color="text.secondary">
                  ROW PROCESSING PROGRESS
                </Typography>
                <Typography variant="caption" sx={{ fontWeight: 700 }}>
                  {processed.toLocaleString()} / {totalRows.toLocaleString()} ({progress}%)
                </Typography>
              </Box>
              <LinearProgress
                variant="determinate"
                value={progress}
                sx={{ height: 8, borderRadius: 4, backgroundColor: '#E2E8F0' }}
              />
            </Box>

            <Grid container spacing={2}>
              <Grid item xs={12} sm={4}>
                <Typography variant="caption" color="text.secondary">
                  Total Rows
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {totalRows.toLocaleString()}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={4}>
                <Typography variant="caption" color="text.secondary">
                  Rows Processed
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {processed.toLocaleString()}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={4}>
                <Typography variant="caption" color="text.secondary">
                  Remaining Rows
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {Math.max(0, totalRows - processed).toLocaleString()}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={4}>
                <Typography variant="caption" color="text.secondary">
                  Started
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {job.created_at ? new Date(job.created_at).toLocaleString() : 'N/A'}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={4}>
                <Typography variant="caption" color="text.secondary">
                  Last Updated
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {job.updated_at ? new Date(job.updated_at).toLocaleString() : 'N/A'}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={4}>
                <Typography variant="caption" color="text.secondary">
                  Source
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {job.source || 'Unknown source'}
                </Typography>
              </Grid>
            </Grid>

            {job.error && (
              <Alert severity="error" sx={{ mt: 2 }}>
                {job.error}
              </Alert>
            )}

            <Alert severity="info" sx={{ mt: 2.5 }}>
              Row-level ingestion results are emitted by the backend ingestion pipeline. Job status, counts, and
              progress above are served by the authoritative registry endpoint.
            </Alert>
          </CardContent>
        </Card>
      )}
    </Box>
  );
}
