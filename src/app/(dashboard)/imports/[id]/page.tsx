'use client';

import React from 'react';
import { useRouter } from 'next/navigation';
import { Box, Card, CardContent, Button, Typography, Alert } from '@mui/material';
import { ArrowLeft, Upload } from 'lucide-react';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';

export default function ImportDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = React.use(params);
  const router = useRouter();

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

      <Card>
        <CardContent sx={{ p: 3 }}>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, mb: 2 }}>
            <Box sx={{ p: 1.2, borderRadius: 2, backgroundColor: '#EFF6FF', color: 'primary.main' }}>
              <Upload size={24} />
            </Box>
            <Typography variant="h6" sx={{ fontWeight: 700 }}>
              Import Job #{id}
            </Typography>
          </Box>
          <Alert severity="info">
            Detailed row-level import results are served by the backend ingestion endpoint. The job list,
            status, and progress are available on the Imports registry.
          </Alert>
        </CardContent>
      </Card>
    </Box>
  );
}
