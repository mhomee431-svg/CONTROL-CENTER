'use client';

import React from 'react';
import { Alert, Box, Button, Typography } from '@mui/material';
import { useRouter } from 'next/navigation';
import { ShieldAlert } from 'lucide-react';

export function AccessDenied({ capability }: { capability?: string }) {
  const router = useRouter();
  return (
    <Box sx={{ maxWidth: 640, mx: 'auto', py: 8 }}>
      <Alert severity="error" icon={<ShieldAlert />} sx={{ mb: 2 }}>
        <Typography variant="h6" sx={{ fontWeight: 700, mb: 0.5 }}>
          Access Denied (403)
        </Typography>
        <Typography variant="body2">
          Your admin role is not authorized to access this control-center area.
          {capability ? ` Required capability: ${capability}.` : ''}
        </Typography>
      </Alert>
      <Button variant="contained" onClick={() => router.replace('/dashboard')}>
        Return to Dashboard
      </Button>
    </Box>
  );
}
