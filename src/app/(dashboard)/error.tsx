'use client';

import React from 'react';
import { Box, Typography, Button, Alert, Paper } from '@mui/material';
import { AlertTriangle, RefreshCw, Home } from 'lucide-react';

/**
 * Route-level error boundary.
 *
 * Without this, any render-time throw inside a dashboard route tears down the
 * entire console — an operator would see a blank screen instead of the rest of
 * the control center. This keeps the failure scoped to the affected panel.
 */
export default function DashboardError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  React.useEffect(() => {
    // Surface the failure for platform diagnostics.
    console.error('[AdminControlCenter] Route error:', error);
  }, [error]);

  return (
    <Box sx={{ p: 3 }}>
      <Paper sx={{ p: 4, border: '1px solid #FECACA', borderRadius: 2 }}>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, mb: 2 }}>
          <AlertTriangle size={28} color="#DC2626" />
          <Typography variant="h6" sx={{ fontWeight: 700 }}>
            This section could not be displayed
          </Typography>
        </Box>

        <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
          An unexpected error occurred while rendering this panel. The rest of the control center
          is unaffected. If this repeats, check the backend service health before retrying.
        </Typography>

        <Alert severity="error" sx={{ mb: 3, fontFamily: 'monospace', fontSize: '0.8125rem' }}>
          {error.message || 'Unknown rendering error'}
          {error.digest && ` (digest: ${error.digest})`}
        </Alert>

        <Box sx={{ display: 'flex', gap: 1.5, flexWrap: 'wrap' }}>
          <Button variant="contained" startIcon={<RefreshCw size={16} />} onClick={() => reset()}>
            Retry
          </Button>
          <Button
            variant="outlined"
            startIcon={<Home size={16} />}
            onClick={() => {
              window.location.href = '/dashboard';
            }}
          >
            Back to Dashboard
          </Button>
        </Box>
      </Paper>
    </Box>
  );
}